# 元 kakasi_parser gem (https://github.com/yamamuteki/kakasi_parser) のポート。
# Zeitwerk autoload で Kakasi (lib/kakasi.rb) も自動的に解決される。
module KakasiParser
  module_function

  def parse(kakasi_result)
    kakasi_result.scan(/[^{}]+/)
                 .map { |match| match.split("|") }
                 .reduce { |a, b| a.product(b) }
                 .map { |reading| reading.is_a?(Array) ? reading.join : reading }
  end

  def kakasi(options, original)
    parse(Kakasi.kakasi(options, original))
  end
end
