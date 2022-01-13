require './lib/lite_orm'
require 'minitest/autorun'
require 'minitest/rg'

module LiteOrm
  module Testing
    class Test < Minitest::Test
      def setup
        LiteOrm.client(reset: true)
      end
    end

    class Foo < LiteOrm::Base
      define_column_for_schema :id, 'INT'
      define_column_for_schema :name, 'TEXT'

      define_index :by_id, :id, unique: true

      self.table_name = :foos
      self.primary_key = :id
    end

    class Bar < LiteOrm::Base
      define_column_for_schema :id_string, 'TEXT'
      define_column_for_schema :age, 'INT'

      define_index :by_id_string, :id, unique: true

      self.table_name = :bars
      self.primary_key = :id_string
    end
  end
end

LiteOrm.sqlite_database_file = './test/assets/db.sqlite'
