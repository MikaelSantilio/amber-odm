require 'amber_odm/version'
require 'elasticsearch'

module AmberODM

  def self.databases_settings
    @databases_settings ||= {}
  end

  module Connector

    # @return [Elasticsearch::Client] The database client
    def self.database(db_name)
      if databases_instances[db_name].nil?
        db_settings = AmberODM.databases_settings[db_name]
        raise Exceptions::MissingDatabaseSettings.new("Database settings not found for #{db_name}") if db_settings.nil? || db_settings.empty?
        self.databases_instances[db_name] = Elasticsearch::Client.new(db_settings)
      end
      databases_instances[db_name]
    end

    def self.databases_instances
      @databases_instances ||= {}
    end
  end

  class AttrInitializer
    attr_reader :_document

    def initialize(document)
      self.class.fields.each do |field|
        document_value = document&.dig(field).dup
        send("#{field}=", document_value) unless document_value.nil?
      end
      instance_variable_set('@document', document)
    end

    # @return [Array]
    def self.fields
      public_instance_methods = self.public_instance_methods(false).grep(/=$/)
      rejected_attr_names = %w[document]
      fields = []
      public_instance_methods.each do |attr|
        attr_name = attr.to_s.gsub('=', '')
        next if rejected_attr_names.include?(attr_name)
        fields << attr_name
      end
      fields
    end

    def nil?
      _document.nil? || _document.empty?
    end

    def self.array_to_h(array)
      array.map do |item|
        if item.is_a?(AttrInitializer)
          item.to_h
        elsif item.is_a?(Array)
          array_to_h(item)
        else
          item
        end
      end
    end

    def to_h
      hash = {}
      known_fields = self.class.fields
      unknown_fields = _document.keys - known_fields
      unknown_fields.reject! { |field| field.start_with?('_') }
      known_fields.each do |field|
        value = send(field)
        if value.is_a?(AttrInitializer)
          hash[field] = value.to_h
        elsif value.is_a?(Array)
          hash[field] = self.class.array_to_h(value)
        else
          hash[field] = value
        end
      end
      unknown_fields.each do |field|
        value = _document[field]
        hash[field] = value
      end

      hash
    end
  end

  class Document < AttrInitializer

    attr_reader :_id, :_score, :sort, :_seq_no, :_primary_term

    def initialize(document)
      @_id = document&.dig('_id').dup
      @_score = document&.dig('_score').dup
      @sort = document&.dig('sort').dup
      @_seq_no = document&.dig('_seq_no').dup
      @_primary_term = document&.dig('_primary_term').dup
      fields = self.class.fields
      fields.each do |field|
        if ['_id', '_score', 'sort', '_seq_no', '_primary_term'].include?(field)
          raise Exceptions::ReservedField.new("Field #{field} is reserved, remove it from the fields list")
        end
        document_value = document&.dig('_source')&.dig(field).dup
        send("#{field}=", document_value)
      end
      instance_variable_set('@_document', document)
    end

    # @return [Symbol, nil]
    def self.db_name
      nil
    end

    # @return [Symbol, String, nil]
    def self.index_name
      nil
    end

    def self.use_seq_verification
      true
    end

    # @return [Elasticsearch::Client] The ES client
    def self.client
      Connector.database(db_name&.to_sym)
    end

    def self.is_valid_fields?(query_fields)
      (query_fields - fields).count == 0
    end

    # @param [Hash] query The query
    # @param [Array] _source The _source
    # @param [Hash] sort The sort
    # @param [Integer] size The size
    # @return [Array<self>] The documents
    def search(query, _source: [], sort: [], search_after: [], size: 0)
      # self.class.validate_fields_from_stages(query, _source, sort)
      if _source.empty?
        _source = self.class.fields
      end

      if query.empty?
        raise Exceptions::IllegalArgumentException.new
      end

      body = { _source: _source, query: query }
      body[:seq_no_primary_term] = true if self.class.use_seq_verification
      body[:sort] = sort unless sort.empty?
      body[:search_after] = search_after unless search_after.empty?
      body[:size] = size unless size.zero?
      response = self.class.client.search(index: self.class.index_name.to_s, body: body)
      response&.dig('hits', 'hits')&.map { |document| self.class.new(document) } || []
    end

    def self.search(filter, _source: [], sort: {}, search_after: [], size: 0)
      new({}).search(filter, _source: _source, sort: sort, search_after: search_after, size: size)
    end

    def self.validate_fields(fields_to_validate)
      fields_to_validate.map! { |field| field.to_s }
      if (fields_to_validate - fields).count > 0
        raise Exceptions::UnknownWriteFieldException.new "Unknown fields: #{fields_to_validate - fields}, define them in attr_accessor before using them"
      elsif fields_to_validate.empty?
        raise Exceptions::IllegalArgumentException.new 'Empty fields'
      end
    end

    def get_bulk_update_hash(*fields)
      self.class.validate_fields(fields)

      aggregation_hash = {}
      fields.each do |field|
        value = send(field)
        if value.is_a?(AttrInitializer)
          aggregation_hash[field] = value.to_h
        elsif value.is_a?(Array)
          aggregation_hash[field] = AttrInitializer.array_to_h(value)
        else
          aggregation_hash[field] = value
        end
      end

      update_hash = {
        update: {
          _index: self.class.index_name&.to_s,
          _id: _id,
          data: { doc: aggregation_hash }
        }
      }
      if self.class.use_seq_verification
        update_hash[:update][:if_seq_no] = _seq_no
        update_hash[:update][:if_primary_term] = _primary_term
      end
      update_hash
    end

  end

  module Exceptions
    class MissingDatabaseSettings < StandardError; end
    class ReservedField < StandardError; end
    class UnknownWriteFieldException < StandardError; end
    class IllegalArgumentException < StandardError
      def initialize(msg = 'query malformed, empty clause')
        super
      end
    end
  end
end