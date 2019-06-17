require 'active_model'

module Mariposta
  module Serializers
    # == Active Model YAML Serializer
    module YAML
      extend ActiveSupport::Concern
      include ActiveModel::Serialization

      included do
        extend ActiveModel::Naming

        class_attribute :include_root_in_json
        self.include_root_in_json = false
      end

      module ClassMethods
        def new_from_yaml(yml)
          new.from_yaml(yml)
        end
      end

      # Same thing as as_json, but returns yaml instead of a hash (unless you include the as_hash:true option)
      def as_yaml(options = {})
        as_hash = options.delete(:as_hash)
        hash = serializable_hash(options)

        # we don't like DateTime in YML. Needs to be just Time.
        hash.each do |k,v|
          if v.nil?
            # we don't want to save nil values as empty front matter variables
            hash.delete(k)
          elsif v.is_a?(DateTime)
            hash[k] = v.to_time
          end
        end

        if include_root_in_json
          custom_root = options && options[:root]
          hash = { custom_root || self.class.model_name.element => hash }
        end

        as_hash ? hash : hash.to_yaml
      end

      def from_yaml(yaml)
        hash = SafeYAML.load(yaml)
        hash = hash.values.first if include_root_in_json
        self.assign_attributes(hash)
        self
      end
    end
  end

  module VariableDefinitions
    def variables(*names_arr)
      self.variable_names = names_arr
      names_arr.each do |var_name|
        attr_accessor var_name
      end
    end
  end

  module FilePathDefinitions
    def folder(path)
      self.folder_path = path
    end
  end
end
