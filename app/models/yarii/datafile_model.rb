require 'safe_yaml'
require 'fileutils'
require 'rake'

class Yarii::DatafileModel
  include ActiveModel::Model
  extend ActiveModel::Callbacks
  define_model_callbacks :save, :destroy

  include Yarii::Serializers::YAML
  extend Yarii::VariableDefinitions
  extend Yarii::FilePathDefinitions

  # override in ApplicationContentModel
  class_attribute :base_path, instance_accessor: false, default: ""

  # override in subclass model
  class_attribute :folder_path, instance_accessor: false, default: ""

  class_attribute :variable_names, instance_accessor: false, default: []

  attr_accessor :file_path, :key_path

  # code snippet from Jekyll
  CHECK_BASE_64_REGEXP = /^([A-Za-z0-9+\/]{4})*([A-Za-z0-9+\/]{4}|[A-Za-z0-9+\/]{3}=|[A-Za-z0-9+\/]{2}==)$/
  PAGINATION_SIZE = 12

  def self.find(file_path, key_path)
    raise "Missing base path for the #{self.name} content model" if self.base_path.blank?

    # decode Base64 path if necessary
    if CHECK_BASE_64_REGEXP.match file_path
      file_path = Base64::decode64 file_path
    end

    file_path = absolute_path(file_path)

    new(file_path: file_path, key_path: key_path).tap do |content_model|
      content_model.load_file_from_path
    end
  end

  def self.absolute_path(path)
    sanitize_filepath File.join(self.base_path, self.folder_path, path)
  end

  def self.sanitize_filepath(path)
    if path.include? "../"
      # TODO: output better error message ;)
      raise "Nice try, Hacker Dude. You lose."
    end

    path
  end

  def self.all(file_path)
    raise "Missing base path for the #{self.name} content model" if self.base_path.blank?
  
    if CHECK_BASE_64_REGEXP.match file_path
      file_path = Base64::decode64 file_path
    end

    file_path = absolute_path(file_path)

    file_data = File.read(file_path)

    loaded_variables = {}

    yaml_data = nil

    begin
      yaml_data = ::SafeYAML.load(file_data)
    end

    if yaml_data.nil?
      raise "YAML wasn't loadable"
    end

    models = []

    if yaml_data.is_a? Array
      yaml_data.each_with_index do |item, index|
        models << new(file_path: file_path, key_path: index.to_s).tap do |content_model|
          content_model.load_file_from_path
        end
      end
    else
      yaml_data = ActiveSupport::HashWithIndifferentAccess.new(yaml_data)
      yaml_data.keys.each do |key|
        models << new(file_path: file_path, key_path: key.to_s).tap do |content_model|
          content_model.load_file_from_path
        end
      end
    end

    models
  end

  def save
    run_callbacks :save do
      if file_path.blank?
        raise "Must supply a file path to save to"
      end

      file_data = File.read(file_path)

      loaded_variables = {}
  
      yaml_data = nil

      begin
        yaml_data = ::SafeYAML.load(file_data)
      end

      if yaml_data.nil?
        raise "YAML wasn't loadable"
      end

      final_data = nil

      if yaml_data.is_a? Array
        yaml_data.set_keypath(key_path, as_yaml(as_hash: true))
        final_data = yaml_data.to_yaml
      else
        yaml_data = ActiveSupport::HashWithIndifferentAccess.new(yaml_data)
        yaml_data.set_keypath(key_path, as_yaml(as_hash: true))
        final_data = yaml_data.to_hash.to_yaml
      end

      final_data.sub!(/^---$\n/,'') # strip off the leading dashes

      File.open(file_path, 'w') do |f|
        f.write(final_data)
      end

      # TODO: figure out a better way to hook in repo updates
  #    Yarii::Repository.current&.add(file_path_to_use)

      true
    end
  end

  def destroy
    # TODO: what does it mean to destroy a keypath?
    raise "TBD"
    run_callbacks :destroy do
      if persisted?
        File.delete(file_path)
      # TODO: figure out a better way to hook in repo updates
  #      Yarii::Repository.current&.remove(file_path)
        self.file_path = nil

        true
      end
    end
  end

  def id
    if persisted?
      relative_base = File.join(self.class.base_path, self.class.folder_path)
      relative_path = file_path.sub(/^#{relative_base}/, '')
      Base64.encode64(relative_path).strip
    end
  end

  def persisted?
    file_path.present? && File.exist?(file_path)
  end
  def new_record?
    !persisted?
  end

  def file_name
    file_path&.split('/')&.last
  end

  def file_stat
    if persisted?
      @file_stat ||= File.stat(file_path)
    end
  end

  def posted_datetime
    if variable_names.include?(:date) && date
      date.to_datetime
    elsif persisted?
      file_stat.mtime
    end
  end

  def variable_names
    @variable_names ||= self.class.variable_names&.dup || []
  end

  def attributes
    ret = {}
    variable_names.each do |var_name|
      ret[var_name.to_s] = nil
    end
    ret
  end

  def assign_attributes(new_attributes)
    # Changed from Active Model
    # (we implement our own method of assigning attributes)

    if !new_attributes.respond_to?(:stringify_keys)
      raise ArgumentError, "When assigning attributes, you must pass a hash as an argument."
    end
    return if new_attributes.empty?

    attributes = new_attributes.stringify_keys
    update_variables(sanitize_for_mass_assignment(attributes))
  end

  def update_variables(hash)
    hash.each do |key, value|
      begin
        send("#{key}=", value)
      rescue NoMethodError
        Rails.logger.warn (":#{key}: is not a defined front matter variable, will be available as read-only")

        # If an unfamiliar variable is present, allow it to be set as a
        # read-only value for future serialization, but it still can't be set
        # via an accessor writer. Kind ugly code, but it works
        instance_variable_set("@#{key}", value)
        unless key.to_sym.in? variable_names
          variable_names << key.to_sym
          define_singleton_method key.to_sym do
            instance_variable_get("@#{key}")
          end
        end
      end
    end
  end

  def load_file_from_path
    raise "Missing keypath" if key_path.nil?
    file_data = File.read(file_path)

    loaded_variables = {}

    begin
      yaml_data = ::SafeYAML.load(file_data)
      loaded_variables = yaml_data.value_at_keypath(key_path)
    rescue SyntaxError => e
      Rails.logger.error "Error: YAML Exception reading #{file_path}: #{e.message}"
    end

    if loaded_variables.present?
      update_variables(loaded_variables)
    end
  end

end
