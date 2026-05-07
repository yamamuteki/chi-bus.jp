# 検索用キーワード (BusStop#keyword) を生成・永続化する rake タスク群。
#
# generate: kakasi で停留所名を漢字 → ローマ字 / ひらがな / カタカナに変換し、空白区切りで連結して保存。
#           この文字列が `lower(...) LIKE lower(...)` の検索対象となり、漢字・かな・ローマ字の
#           どの入力でもヒットするようになる（BusStopsController#index の検索ロジック）。
# load:     db/data/keywords.csv を DB に bulk UPDATE で投入する。
#
# generate は kakasi_parser gem と OS の kakasi コマンドを要求する。
# Dockerfile.dev に kakasi を入れているので Docker 環境ならそのまま動く。
# 通常のセットアップでは generate ではなく load を使う（kakasi 実行時間の節約）。
namespace :keyword do
  desc "Load keywords from db/data/keywords.csv"
  task load: :environment do
    csv_path = "db/data/keywords.csv"
    raise "Missing #{csv_path}. Run 'rails keyword:generate' first." unless File.exist?(csv_path)

    raw = ActiveRecord::Base.connection.raw_connection
    ActiveRecord::Base.transaction do
      # temp table 経由の bulk UPDATE。ON COMMIT DROP でトランザクション終了時に自動廃棄。
      raw.exec("CREATE TEMP TABLE _tmp_keywords (bus_stop_id INTEGER, keyword TEXT) ON COMMIT DROP")

      raw.copy_data("COPY _tmp_keywords (bus_stop_id, keyword) FROM STDIN WITH CSV HEADER") do
        File.open(csv_path, "r") do |f|
          while (line = f.gets)
            raw.put_copy_data(line)
          end
        end
      end

      # 1 SQL で全件 UPDATE。
      raw.exec(<<~SQL)
        UPDATE bus_stops AS bs
        SET keyword = t.keyword
        FROM _tmp_keywords AS t
        WHERE bs.id = t.bus_stop_id
      SQL
    end
    puts "Loaded #{csv_path}"
  end

  desc "Generate keywords into db/data/keywords.csv (does not touch DB)"
  task generate: :environment do
    require "csv"
    csv_path = "db/data/keywords.csv"

    # find_each はデフォルトで id ASC でバッチ取得するため、出力 CSV は自動的に id 順に揃う。
    # CSV.open のブロック内で 1 行ずつストリーミング書き出しすることで、5 万件分をメモリに
    # ためずに済む（前バージョンは rows 配列に全件蓄積していた）。
    $stdout.sync = true
    total = BusStop.count
    CSV.open(csv_path, "w", headers: %w[bus_stop_id keyword], write_headers: true) do |csv|
      skipped = 0
      BusStop.find_each do |bus_stop|
        # kakasi のオプション解説（末尾の文字が「変換先」、それより前の大文字が「変換元」）:
        #   -Ja -Ha -Ka -ka -Ea -p
        #     漢字(J) / ひらがな(H) / カタカナ(K) / 半角カナ(k) / ASCII記号(E) を全て ASCII (a) = ローマ字に
        #   -JH -aH -KH -kH -EH -p
        #     全部ひらがな(H)に
        #   -JK -aK -HK -kK -EK -p
        #     全部カタカナ(K)に
        #   -p は曖昧な漢字読みの全候補を出力する（読みのバリエーションをまとめてヒットさせるため）
        # `.delete("^")` は kakasi が候補区切りに出す `^` を取り除いて 1 つのフラットな文字列にする処理。
        keyword =
          begin
            [
              bus_stop.name,
              KakasiParser.kakasi("-Ja -Ha -Ka -ka -Ea -p", bus_stop.name).join(" ").delete("^"),
              KakasiParser.kakasi("-JH -aH -KH -kH -EH -p", bus_stop.name).join(" "),
              KakasiParser.kakasi("-JK -aK -HK -kK -EK -p", bus_stop.name).join(" ")
            ].join(" ")
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            # kakasi は内部で CP932 (Windows-31J) を使うため、CP932 で表現できない
            # 漢字 (例: 箞) を含む停留所名は変換に失敗する。その場合は name 単体を
            # キーワードとして登録する。漢字での検索は引き続きヒットするが、
            # ローマ字 / かな経由での検索はできない (極希なケースなので許容)。
            skipped += 1
            bus_stop.name
          end
        csv << [ bus_stop.id, keyword ]
      end
      puts "  CP932 unconvertible names skipped: #{skipped}" if skipped.positive?
    end
    puts "Wrote #{csv_path} (#{total} rows)"
  end
end
