require "ffi"

# 元 kakasi gem (https://github.com/m-tom-h/kakasi-ruby) のポート。
# パブリック API は元 gem と同じく `Kakasi.kakasi(options, text) -> String`。
#
# libkakasi.so.2 を FFI で動的にロードして in-process で叩く。元 gem は
# fiddle / ffi の 2 backend を持っていたが、Ruby LSP との相性で C 拡張系を
# 避けたいため ffi gem (libffi の Ruby バインディング、ビルド不要) のみ使う。
#
# libkakasi はグローバル単一状態なので options が変わるたびに
# kakasi_close_kanwadict + kakasi_getopt_argv で辞書を載せ替える (元 gem 同様)。
# Pointer#read_string は C 文字列セマンティクスで NUL の手前まで読むため、
# kakasi が出力に NUL+junk を挿むケース (CP932 で表現できない記号など) も
# 自動的に切り落とされる。
module Kakasi
  module Lib
    extend FFI::Library

    # libkakasi.so.2 は keyword:generate でしか使わないが、Zeitwerk が production
    # 起動時に lib/ を eager load するため、Heroku などライブラリが無い環境でも
    # ロード時に落ちないよう begin/rescue で防御する。Kakasi.kakasi 呼び出し時に
    # 改めて raise させる。
    AVAILABLE = begin
      ffi_lib "libkakasi.so.2"
      attach_function :kakasi_getopt_argv, [ :int, :pointer ], :int
      attach_function :kakasi_do, [ :string ], :pointer
      attach_function :kakasi_close_kanwadict, [], :int
      attach_function :kakasi_free, [ :pointer ], :int
      true
    rescue LoadError
      false
    end
  end

  INTERNAL_ENCODING = Encoding::CP932

  @mutex = Mutex.new
  @options = nil

  module_function

  def kakasi(options, string)
    raise LoadError, "libkakasi.so.2 not available (install kakasi package)" unless Lib::AVAILABLE

    @mutex.synchronize do
      if options != @options
        Lib.kakasi_close_kanwadict if @options
        args = [ "kakasi", *options.split ]
        argv = FFI::MemoryPointer.new(:pointer, args.size).write_array_of_pointer(
          args.map { |arg| FFI::MemoryPointer.from_string(arg) }
        )
        Lib.kakasi_getopt_argv(args.size, argv).zero? or raise "failed to initialize kakasi"
        @options = options.dup
      end

      encoding = string.encoding
      result = "".force_encoding(INTERNAL_ENCODING)
      string.encode(INTERNAL_ENCODING).split(/(\0+)/).each do |str, nul|
        buf = Lib.kakasi_do(str)
        result << buf.read_string.force_encoding(INTERNAL_ENCODING)
        Lib.kakasi_free(buf)
        result << nul if nul
      end
      result.encode(encoding)
    end
  end
end
