require 'fileutils'
require 'sqlite3'

module LiteOrm
  class << self
    def sqlite_database_file=(input)
      @sqlite_database_file = input
    end

    def sqlite_database_file
      @sqlite_database_file
    end

    def client(uncache: false, reset: false)
      @client = nil if uncache || reset

      if @client
        @client
      else
        destroy_database_file! if reset
        ensure_database_file_exists!

        @client = SQLite3::Database.new(sqlite_database_file)

        @client
      end
    end

    def reset!
      client(reset: true)
    end

    def destroy_database_file!
      FileUtils.rm_f(sqlite_database_file)
    end

    def ensure_database_file_exists!
      FileUtils.touch(sqlite_database_file)
    end
  end

  class Base
    FIND_BY_XXX_REGEX = %r/\Afind_by_(\w+)\z/

    class << self
      def table_name=(table_name)
        @table_name = table_name.to_sym
      end

      def table_name
        @table_name
      end

      def primary_key=(primary_key)
        @primary_key = primary_key.to_sym
      end

      def primary_key
        @primary_key
      end

      def define_column_for_schema(column_name, type)
        @manually_defined_schema ||= {}
        @manually_defined_schema[column_name.to_sym] = {
          type: type
        }
      end

      def schema
        @manually_defined_schema || {}
      end

      def convert_for_sqlite(column_name, value)
        case sqlite_column_type(column_name)
        when 'INT'
          value.to_s
        when 'TEXT'
          "'#{value.to_s}'"
        else
          'NULL'
        end
      end

      def sqlite_schema_string
        StringIO.new.tap do |s|
          s.print('(')
          schema.each_with_index do |(column_name, column_attrs), index|
            s.print(',') unless index.zero?

            s.print(column_name)
            s.print(' ')
            s.print(column_attrs[:type])
          end
          s.print(')')
        end.string
      end

      def ensure_table_exists!
        LiteOrm.client.execute("CREATE TABLE IF NOT EXISTS #{table_name}#{sqlite_schema_string}")
      end

      def define_index(index_name, *columns, unique: false)
        @manually_defined_indexes ||= {}
        @manually_defined_indexes[index_name.to_sym] = {
          columns: columns,
          unique: unique
        }
      end

      def indexes
        @manually_defined_indexes
      end

      def has_column_defined?(column_name)
        schema.key?(column_name.to_sym)
      end

      def sqlite_column_type(column_name)
        schema.dig(column_name.to_sym, :type)
      end

      # TODO: Make this match method_missing.
      # def respond_to_missing(method_name, include_private)
      # end

      def method_missing(method_name, *args, &block)
        method_name_s = method_name.to_s

        if (match_data=FIND_BY_XXX_REGEX.match(method_name_s))
          potential_attribute_name = match_data.captures[0]

          if potential_attribute_name && has_column_defined?(potential_attribute_name)
            if args.size == 1
              query_result = LiteOrm.client.execute(
                "SELECT * FROM #{table_name} WHERE #{potential_attribute_name}=#{convert_for_sqlite(potential_attribute_name,args[0])} LIMIT 1;"
              )&.[](0)

              if query_result
                self.new(with_query_result: query_result)
              else
                nil
              end
            else
              raise "method #{method_name} requires 1 argument; received #{args.size} arguments."
            end
          else
            super
          end
        else
          super
        end
      end
    end

    def initialize(with_query_result: nil)
      @backend_hash = {}

      if with_query_result
        set_attributes_from_query_result(*with_query_result)
      end
    end

    def save!
      if exist_in_database?
        LiteOrm.client.execute(
          "UPDATE #{self.class.table_name} SET #{attributes_for_update_command};"
        )
      else
        LiteOrm.client.execute(
          "INSERT INTO #{self.class.table_name}#{attribute_names_for_create_command} VALUES #{attribute_values_for_create_command};"
        )
      end
    end

    # TODO: Make this match method_missing.
    # def respond_to_missing(method_name, include_private)
    # end

    def method_missing(method_name, *args, &block)
      method_name_s = method_name.to_s
      potential_assignment = method_name_s.end_with?('=')

      potential_attribute_name =
        if potential_assignment
          method_name_s[0..-2]
        else
          method_name_s
        end

      if potential_assignment && potential_attribute_name && self.class.has_column_defined?(potential_attribute_name)
        if args.size == 1
          set_column_attribute(potential_attribute_name, args[0])
        else
          raise "method #{method_name} requires 1 argument; received #{args.size} arguments."
        end
      elsif potential_attribute_name && self.class.has_column_defined?(potential_attribute_name)
        get_column_attribute(potential_attribute_name)
      else
        super
      end
    end

    private

    def get_column_attribute(column_name)
      @backend_hash[column_name.to_sym]
    end

    def set_column_attribute(column_name, value)
      @backend_hash[column_name.to_sym] = value
    end

    def primary_key_value
      send(self.class.primary_key)
    end

    # NOTE: This doesn't handle the case of changing the primary_key. Suppose
    #   we found this record with a primary_key of 100, if we then change
    #   the primary key to 101(which isn't in the database), then this
    #   method will return false, even though technically it is in the database
    #   with a different primary key.
    def exist_in_database?
      result = LiteOrm.client.execute(
        "SELECT COUNT(*) FROM #{self.class.table_name} WHERE #{self.class.primary_key}='#{primary_key_value}';"
      )
      count = result.dig(0,0)

      count && count > 0
    end

    def attributes_for_update_command(include_primary_key: false)
      schema = self.class.schema

      StringIO.new.tap do |s|
        schema.select do |column_name, column_attrs|
          if include_primary_key
            true
          else
            column_name != self.class.primary_key.to_sym
          end
        end.each_with_index do |(column_name, column_attrs), index|
          my_value = get_column_attribute(column_name)

          s.print(',') unless index.zero?
          s.print(column_name)
          s.print('=')

          if my_value
            case column_attrs[:type]
            when 'INT'
              s.print(my_value.to_s)
            when 'TEXT'
              s.print("'#{my_value}'")
            end
          else
            s.print('NULL')
          end
        end
      end.string
    end

    def attribute_names_for_create_command
      schema = self.class.schema

      StringIO.new.tap do |s|
        s.print('(')
        schema.keys.each_with_index do |column_name, index|
          s.print(',') unless index.zero?
          s.print(column_name)
        end
        s.print(')')
      end.string
    end

    def attribute_values_for_create_command
      schema = self.class.schema

      StringIO.new.tap do |s|
        s.print('(')
        schema.each_with_index do |(column_name, column_attrs), index|
          my_value = send(column_name)

          s.print(',') unless index.zero?

          if my_value
            case column_attrs[:type]
            when 'INT'
              s.print(my_value.to_s)
            when 'TEXT'
              s.print("'#{my_value}'")
            end
          else
            s.print('NULL')
          end
        end
        s.print(')')
      end.string
    end

    def set_attributes_from_query_result(*database_row_attributes)
      @backend_hash.merge!(
        Hash[self.class.schema.keys.zip(database_row_attributes)]
      )
    end
  end
end
