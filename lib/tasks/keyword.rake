# 検索用キーワード (BusStop#keyword) を生成・永続化する rake タスク群。
#
# generate: kakasi で停留所名を漢字 → ローマ字 / ひらがな / カタカナに変換し、空白区切りで連結して保存。
#           この文字列が `lower(...) LIKE lower(...)` の検索対象となり、漢字・かな・ローマ字の
#           どの入力でもヒットするようになる（BusStopsController#index の検索ロジック）。
# dump:     DB の keyword を db/keywords.json に書き出す（永続化）。
# restore:  db/keywords.json から DB に書き戻す。
#
# generate は kakasi_parser gem を要求する。Gemfile では通常コメントアウトされており、
# 再生成時のみ有効化する運用（CLAUDE.md 参照）。通常のセットアップでは restore を使う。
namespace :keyword do
  desc "Generate keywords"
  task generate: :environment do
    progress = ProgressBar.create(title: "Generate", total: BusStop.count, format: "%t: %J%% |%B|")
    ActiveRecord::Base.transaction do
      BusStop.find_each.each do |bus_stop|
        # kakasi のオプション解説（末尾の文字が「変換先」、それより前の大文字が「変換元」）:
        #   -Ja -Ha -Ka -ka -Ea -p
        #     漢字(J) / ひらがな(H) / カタカナ(K) / 半角カナ(k) / ASCII記号(E) を全て ASCII (a) = ローマ字に
        #   -JH -aH -KH -kH -EH -p
        #     全部ひらがな(H)に
        #   -JK -aK -HK -kK -EK -p
        #     全部カタカナ(K)に
        #   -p は曖昧な漢字読みの全候補を出力する（読みのバリエーションをまとめてヒットさせるため）
        # `.delete("^")` は kakasi が候補区切りに出す `^` を取り除いて 1 つのフラットな文字列にする処理。
        keyword = [
          bus_stop.name,
          KakasiParser.kakasi("-Ja -Ha -Ka -ka -Ea -p", bus_stop.name).join(" ").delete("^"),
          KakasiParser.kakasi("-JH -aH -KH -kH -EH -p", bus_stop.name).join(" "),
          KakasiParser.kakasi("-JK -aK -HK -kK -EK -p", bus_stop.name).join(" ")
        ].join(" ")
        bus_stop.update(keyword: keyword)
        progress.increment
      end
    end
  end

  desc "Dump keywords"
  task dump: :environment do
    # DB の keyword を JSON に書き出して永続化する。
    # generate の結果を git にコミット可能な形にして、運用時は restore で再現する。
    progress = ProgressBar.create(title: "Dump", total: BusStop.count, format: "%t: %J%% |%B|")
    File.write("db/keywords.json", JSON.pretty_generate(
      BusStop.find_each.map do |bus_stop|
        progress.increment
        {
          bus_stop_id: bus_stop.id,
          keyword: bus_stop.keyword
        }
      end
    ))
  end

  desc "Restore keywords"
  task restore: :environment do
    # db/keywords.json を読み込み、各 BusStop の keyword を復元する。
    # 通常のセットアップではこちらを使い、kakasi_parser gem の有効化を避ける。
    records = JSON.parse(File.read("db/keywords.json"))
    progress = ProgressBar.create(title: "Restore", total: records.count, format: "%t: %J%% |%B|")
    ActiveRecord::Base.transaction do
      records.each do |record|
        bus_stop = BusStop.find record["bus_stop_id"]
        bus_stop.update(
          keyword: record["keyword"]
        )
        progress.increment
      end
    end
  end
end
