require 'safe_yaml'
require 'rake'

class Yarii::ContentModel
  include ActiveModel::Model
  extend ActiveModel::Callbacks
  define_model_callbacks :create, :update, :destroy

  include Yarii::Serializers::YAML
  extend Yarii::VariableDefinitions
  extend Yarii::FilePathDefinitions

  # override in ApplicationContentModel
  class_attribute :base_path, instance_accessor: false, default: ""

  # override in subclass model
  class_attribute :folder_path, instance_accessor: false, default: ""

  class_attribute :variable_names, instance_accessor: false, default: []

  attr_accessor :file_path, :content

  # code snippet from Jekyll
  YAML_FRONT_MATTER_REGEXP = %r!\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)!m
  CHECK_BASE_64_REGEXP = /^([A-Za-z0-9+\/]{4})*([A-Za-z0-9+\/]{4}|[A-Za-z0-9+\/]{3}=|[A-Za-z0-9+\/]{2}==)$/

  def self.find(file_path)
    raise "Missing base path for the #{self.name} content model" if self.base_path.blank?

    # decode Base64 path if necessary
    if CHECK_BASE_64_REGEXP.match file_path
      file_path = Base64::decode64 file_path
    end

    file_path = path(file_path)

    new(file_path: file_path).tap do |content_model|
      content_model.load_file_from_path
    end
  end

  def self.path(path)
    sanitize_filepath File.join(self.base_path, self.folder_path, path)
  end

  def self.sanitize_filepath(path)
    if path.include? "../"
      # TODO: output better error message ;)
      raise "Nice try, Hacker Dude. You lose."
    end

    path
  end

  def self.all(sorted: true, subfolder: nil)
    raise "Missing base path for the #{self.name} content model" if self.base_path.blank?

    if self.folder_path.present?
      # find all files in the folder and any direct subfolders
      glob_pattern = File.join(self.base_path, self.folder_path, subfolder.to_s, "**/**")

      files = Dir.glob(glob_pattern)
    else
      # find any Markdown or HTML pages not in special underscore folders
      files = Rake::FileList.new(
        File.join(self.base_path, "**/*.md"),
        File.join(self.base_path, "**/*.html")
      ) do |fl|
        basename = Pathname.new(self.base_path).basename.sub(/^_/, '')
        fl.exclude(/#{basename}\/\_/)
      end
    end

    models = files.map do |file_path|
      unless File.directory? file_path
        new(file_path: file_path).tap do |content_model|
          content_model.load_file_from_path
        end
      end
    end.compact

    if sorted
      models.sort_by! {|content_model| content_model.posted_datetime }.reverse
    else
      models
    end
  end

  def save(force_file_path=nil)
    callback_name = new_record? ? :create : :update
    run_callbacks callback_name do
      file_path_to_use = force_file_path || file_path
      if file_path_to_use.blank?
        raise "Must specify a file path"
      end

      File.open(file_path_to_use, 'w') do |f|
        f.write(generate_file_output)
      end

      # TODO: figure out a better way to hook in repo updates
  #    Yarii::Repository.current&.add(file_path_to_use)

      true
    end
  end

  def destroy
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
    file_path.present?
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
    elsif matched = file_name.to_s.match(/^[0-9]+-[0-9]+-[0-9]+/)
      matched[0].to_datetime
    elsif persisted?
      file_stat.mtime
    end
  end

  def generate_file_output
    as_yaml + "---\n\n" + content.to_s
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
    file_data = File.read(file_path)

    loaded_variables = {}

    begin
      if file_data =~ YAML_FRONT_MATTER_REGEXP
        self.content = $'
        loaded_variables = ::SafeYAML.load(Regexp.last_match(1))
      end
    rescue SyntaxError => e
      Rails.logger.error "Error: YAML Exception reading #{file_path}: #{e.message}"
    end

    if loaded_variables.present?
      update_variables(loaded_variables)
    end
  end

end
