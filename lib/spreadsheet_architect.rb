require 'spreadsheet_architect/set_mime_types'
require 'spreadsheet_architect/action_controller_renderers'
require 'axlsx'
require 'spreadsheet_architect/axlsx_column_width_patch'
require 'odf/spreadsheet'
require 'csv'


module SpreadsheetArchitect
  def self.included(base)
    base.send :extend, ClassMethods
  end

  module Helpers

    def self.str_humanize(str, capitalize = true)
      str = str.sub(/\A_+/, '').gsub(/[_\.]/,' ').sub(' rescue nil','')
      if capitalize
        str = str.gsub(/(\A|\ )\w/){|x| x.upcase}
      end
      str
    end

    def self.get_options(options={}, klass)
      has_custom_columns = klass.instance_methods.include?(:spreadsheet_columns)

      if !options[:data] && klass.ancestors.include?(ActiveRecord::Base)
        options[:data] = klass.where(options[:where]).order(options[:order]).to_a
      else
        raise 'No data option was defined. This is required for plain ruby objects.'
      end
      raise NoDataError if options[:data].none?

      if !has_custom_columns && klass.ancestors.include?(ActiveRecord::Base)
        the_column_names = (klass.column_names - ["id","created_at","updated_at","deleted_at"])
        headers = the_column_names.map{|x| str_humanize(x)}
        columns = the_column_names.map{|x| x.to_sym}
      elsif has_custom_columns
        headers = []
        columns = []
        array = options[:spreadsheet_columns] || options[:data].first.spreadsheet_columns
        array.each do |x|
          if x.is_a?(Array)
            headers.push x[0].to_s
            columns.push x[1]
          else
            headers.push str_humanize(x.to_s)
            columns.push x
          end
        end
      else
        raise 'No instance method `spreadsheet_columns` found on this plain ruby object'
      end

      data = []
      options[:data].each do |instance|
        if has_custom_columns && !options[:spreadsheet_columns]
          row_data = []
          instance.spreadsheet_columns.each do |x|
            if x.is_a?(Array)
              row_data.push(x[1].is_a?(Symbol) ? instance.instance_eval(x[1].to_s) : x[1])
            else
              row_data.push(x.is_a?(Symbol) ? instance.instance_eval(x.to_s) : x)
            end
          end
          data.push row_data
        else
          data.push columns.map{|col| col.is_a?(Symbol) ? instance.instance_eval(col.to_s) : col}
        end
      end

      headers = (options[:headers] == false ? false : headers)

      header_style = {background_color: "AAAAAA", color: "FFFFFF", align: :center, bold: false, font_name: 'Arial', font_size: 10, italic: false, underline: false}
      
      if options[:header_style]
        header_style.merge!(options[:header_style])
      elsif options[:header_style] == false
        header_style = false
      end

      row_style = {background_color: nil, color: "000000", align: :left, bold: false, font_name: 'Arial', font_size: 10, italic: false, underline: false}
      if options[:row_style]
        row_style.merge!(options[:row_style])
      end

      sheet_name = options[:sheet_name] || klass.name

      types = (options[:types] || []).flatten

      return {headers: headers, header_style: header_style, row_style: row_style, types: types, sheet_name: sheet_name, data: data}
    end
  end

  module ClassMethods
    def to_csv(opts={})
      options = SpreadsheetArchitect::Helpers.get_options(opts, self)

      CSV.generate do |csv|
        csv << options[:headers] if options[:headers]
        
        options[:data].each do |row_data|
          csv << row_data
        end
      end
    end

    def to_ods(opts={})
      options = SpreadsheetArchitect::Helpers.get_options(opts, self)

      spreadsheet = ODF::Spreadsheet.new

      spreadsheet.office_style :header_style, family: :cell do
        if options[:header_style]
          unless opts[:header_style] && opts[:header_style][:bold] == false #uses opts, temporary
            property :text, 'font-weight': :bold
          end
          if options[:header_style][:align]
            property :text, 'align': options[:header_style][:align]
          end
          if options[:header_style][:size]
            property :text, 'font-size': options[:header_style][:size]
          end
          if options[:header_style][:color] && opts[:header_style] && opts[:header_style][:color] #temporary
            property :text, 'color': "##{options[:header_style][:color]}"
          end
        end
      end
      spreadsheet.office_style :row_style, family: :cell do
        if options[:row_style]
          if options[:row_style][:bold]
            property :text, 'font-weight': :bold
          end
          if options[:row_style][:align]
            property :text, 'align': options[:row_style][:align]
          end
          if options[:row_style][:size]
            property :text, 'font-size': options[:row_style][:size]
          end
          if opts[:row_style] && opts[:row_style][:color] #uses opts, temporary
            property :text, 'color': "##{options[:row_style][:color]}"
          end
        end
      end

      spreadsheet.table options[:sheet_name] do 
        if options[:headers]
          row do
            options[:headers].each do |header|
              cell header, style: :header_style
            end
          end
        end
        options[:data].each do |row_data|
          row do 
            row_data.each do |y|
              cell y, style: :row_style
            end
          end
        end
      end

      return spreadsheet.bytes
    end

    def to_xlsx(opts={})
      options = SpreadsheetArchitect::Helpers.get_options(opts, self)
    
      header_style = {}
      header_style[:fg_color] = options[:header_style].delete(:color)
      header_style[:bg_color] = options[:header_style].delete(:background_color)
      if header_style[:align]
        header_style[:alignment] = {}
        header_style[:alignment][:horizontal] = options[:header_style].delete(:align)
      end
      header_style[:b] = options[:header_style].delete(:bold)
      header_style[:sz] = options[:header_style].delete(:font_size)
      header_style[:i] = options[:header_style].delete(:italic)
      if options[:header_style][:underline]
        header_style[:u] = options[:header_style].delete(:underline)
      end
      header_style.delete_if{|x| x.nil?}

      row_style = {}
      row_style[:fg_color] = options[:row_style].delete(:color)
      row_style[:bg_color] = options[:row_style].delete(:background_color)
      if row_style[:align]
        row_style[:alignment] = {}
        row_style[:alignment][:horizontal] = options[:row_style][:align]
      end
      row_style[:b] = options[:row_style].delete(:bold)
      row_style[:sz] = options[:row_style].delete(:font_size)
      row_style[:i] = options[:row_style].delete(:italic)
      if options[:row_style][:underline]
        row_style[:u] = options[:row_style].delete(:underline)
      end
      row_style.delete_if{|x| x.nil?}
      
      package = Axlsx::Package.new

      return package if options[:data].empty?

      package.workbook.add_worksheet(name: options[:sheet_name]) do |sheet|
        if options[:headers]
          sheet.add_row options[:headers], style: package.workbook.styles.add_style(header_style)
        end
        
        options[:data].each do |row_data|
          sheet.add_row row_data, style: package.workbook.styles.add_style(row_style), types: options[:types]
        end
      end

      return package.to_stream.read
    end
  end
end

class SpreadsheetArchitect::NoDataError < StandardError; end
