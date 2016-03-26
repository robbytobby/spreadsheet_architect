if defined? ActionController
  [:xlsx, :ods, :csv].each do |format|
    ActionController::Renderers.add format do |data, options|
      if data.is_a?(ActiveRecord::Relation)
        options[:filename] = data.model.name.pluralize
        data = data.send("to_#{format}")
      end
      send_data data, type: format, disposition: :attachment, filename: (options[:filename] || 'data').chomp(".#{format}") + ".#{format}"
    end
  end
end
