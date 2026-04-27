require "./colors"

module Cjules
  module Output
    class Table
      def initialize(@headers : Array(String))
        @rows = [] of Array(String)
      end

      def add_row(row : Array(String))
        @rows << row
      end

      def render(io : IO = STDOUT)
        widths = @headers.map(&.size)
        @rows.each do |row|
          row.each_with_index do |cell, i|
            len = Colors.visible_length(cell)
            widths[i] = len if i < widths.size && len > widths[i]
          end
        end

        @headers.each_with_index do |h, i|
          io << pad(Colors.bold(h), widths[i])
          io << "  " unless i == @headers.size - 1
        end
        io.puts

        @rows.each do |row|
          row.each_with_index do |cell, i|
            io << pad(cell, widths[i])
            io << "  " unless i == @headers.size - 1
          end
          io.puts
        end
      end

      private def pad(s : String, width : Int32) : String
        diff = width - Colors.visible_length(s)
        diff <= 0 ? s : s + " " * diff
      end
    end
  end
end
