require "csv"
require "fileutils"
require "json"
require "zlib"

# stitch:generate が出力する db/data/stitches.csv.gz の読み書きを担当する。
#
# レコード形は (route_id, start_repr) 複合キー。1 路線につき 1 〜 2 行 (selector 起点 A と
# fallback 起点 B = nil)。pick_best_assignment が両候補を比較するために両方を読み出す。
#
# 各列の意味:
#   - route_id, start_repr     ... 複合キー
#   - flat_coords (JSON 配列)   ... 採番に使う 1D 化された座標列
#   - bridge_segment_indices   ... numberer が射影対象から除外する virtual segment の index
#   - total_tracks ... isolated_count, max_jump_distance ... connection_count
#                              ... diagnose タスクが消費する stitch メトリクス
#
# stitch:load は無い: production はこの中間ファイルを読まないので DB に投入しない。
# bus_stop_number:generate / diagnose のみが offline で読み出す。
module StitchStore
  STITCHES_PATH = "db/data/stitches.csv.gz".freeze

  COLUMNS = %w[
    route_id start_repr flat_coords bridge_segment_indices
    total_tracks skipped_parallel reversed_count isolated_count
    max_jump_distance large_jump_count connection_jump_max
    connection_large_jump_count connection_count
  ].freeze

  # cache から復元する stitch 結果のレコード型。
  # TrackStitcher::Result とフィールドをそろえてあるが、stitch_steps だけは inspect task
  # でしか使わず、CSV に出すと巨大になるので除外する。
  Entry = Struct.new(
    :flat_coords,
    :bridge_segment_indices,
    :total_tracks,
    :skipped_parallel,
    :reversed_count,
    :isolated_count,
    :max_jump_distance,
    :large_jump_count,
    :connection_jump_max,
    :connection_large_jump_count,
    :connection_count,
    keyword_init: true
  )

  def self.path
    Rails.root.join(STITCHES_PATH)
  end

  # `start` (= [lat, lng] 配列 or nil) を CSV 行内のキー文字列に変換する。
  # 浮動小数点の表現は同一プロセス内で安定なので to_s ベースの単純連結で十分。
  def self.encode_start(start)
    start.nil? ? "nil" : "#{start[0]}:#{start[1]}"
  end

  # CSV を読み込んで {(route_id, start_repr) => Entry} の Hash で返す。
  # ファイル不在なら空 Hash。
  def self.load_existing
    return {} unless File.exist?(path)

    map = {}
    Zlib::GzipReader.open(path) do |gz|
      CSV.new(gz, headers: true).each do |row|
        key = [ row["route_id"].to_i, row["start_repr"] ]
        map[key] = Entry.new(
          flat_coords: JSON.parse(row["flat_coords"]),
          bridge_segment_indices: JSON.parse(row["bridge_segment_indices"]),
          total_tracks: row["total_tracks"].to_i,
          skipped_parallel: row["skipped_parallel"].to_i,
          reversed_count: row["reversed_count"].to_i,
          isolated_count: row["isolated_count"].to_i,
          max_jump_distance: row["max_jump_distance"].to_f,
          large_jump_count: row["large_jump_count"].to_i,
          connection_jump_max: row["connection_jump_max"].to_f,
          connection_large_jump_count: row["connection_large_jump_count"].to_i,
          connection_count: row["connection_count"].to_i
        )
      end
    end
    map
  end

  # Hash を CSV.gz に書き出す (route_id, start_repr 順でソート)。
  def self.write(map)
    FileUtils.mkdir_p(File.dirname(path))
    Zlib::GzipWriter.open(path) do |gz|
      csv = CSV.new(gz, headers: COLUMNS, write_headers: true)
      map.sort.each do |(route_id, start_repr), entry|
        csv << [
          route_id,
          start_repr,
          JSON.generate(entry.flat_coords),
          JSON.generate(entry.bridge_segment_indices),
          entry.total_tracks,
          entry.skipped_parallel,
          entry.reversed_count,
          entry.isolated_count,
          entry.max_jump_distance,
          entry.large_jump_count,
          entry.connection_jump_max,
          entry.connection_large_jump_count,
          entry.connection_count
        ]
      end
    end
    path
  end

  # TrackStitcher::Result から CSV 用 Entry を作る。
  def self.entry_from_result(result)
    Entry.new(
      flat_coords: result.flat_coords,
      bridge_segment_indices: result.bridge_segment_indices,
      total_tracks: result.total_tracks,
      skipped_parallel: result.skipped_parallel,
      reversed_count: result.reversed_count,
      isolated_count: result.isolated_count,
      max_jump_distance: result.max_jump_distance,
      large_jump_count: result.large_jump_count,
      connection_jump_max: result.connection_jump_max,
      connection_large_jump_count: result.connection_large_jump_count,
      connection_count: result.connection_count
    )
  end

  # CSV 由来の Entry から TrackStitcher::Result 形のオブジェクトを作る。
  # bus_stop_number:generate / diagnose は stitch.flat_coords, stitch.bridge_segment_indices,
  # 各メトリクス列を使うが stitch_steps は使わないため、stitch_steps は空配列で埋める。
  def self.result_from_entry(entry)
    TrackStitcher::Result.new(
      flat_coords: entry.flat_coords,
      total_tracks: entry.total_tracks,
      skipped_parallel: entry.skipped_parallel,
      reversed_count: entry.reversed_count,
      isolated_count: entry.isolated_count,
      max_jump_distance: entry.max_jump_distance,
      large_jump_count: entry.large_jump_count,
      connection_jump_max: entry.connection_jump_max,
      connection_large_jump_count: entry.connection_large_jump_count,
      connection_count: entry.connection_count,
      stitch_steps: [],
      bridge_segment_indices: entry.bridge_segment_indices
    )
  end
end
