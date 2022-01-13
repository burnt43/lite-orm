require './test/initialize'

module LiteOrm
  module Testing
    class BaseTest < LiteOrm::Testing::Test
      def test_schema
        s = LiteOrm::Testing::Foo.schema

        assert(s.key?(:id))
        assert(s.key?(:name))
        assert_equal('INT', s.dig(:id, :type))
        assert_equal('TEXT', s.dig(:name, :type))
      end

      def test_sqlite_schema_string
        s = LiteOrm::Testing::Foo.sqlite_schema_string

        assert_equal('(id INT,name TEXT)', s)
      end

      def test_indexes
        i = LiteOrm::Testing::Foo.indexes
        assert(i.key?(:by_id))
        assert_includes(i.dig(:by_id, :columns), :id)
        assert(i.dig(:by_id, :unique))
      end

      def test_attribute_assignment
        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.name = 'Electric Aunt Jemima'
          f.id = 16
        end

        assert_equal('Electric Aunt Jemima', foo01.instance_eval{@backend_hash[:name]})
        assert_equal(16, foo01.instance_eval{@backend_hash[:id]})
      end

      def test_attribute_retrieval
        foo01 = LiteOrm::Testing::Foo.new

        foo01.instance_eval{@backend_hash[:name] = 'Stewart Rowland'}
        foo01.instance_eval{@backend_hash[:id] = 1}

        assert_equal('Stewart Rowland', foo01.name)
        assert_equal(1, foo01.id)
      end

      def test_attributes_for_update_command
        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        assert_equal("name='Joe Blow'", foo01.send(:attributes_for_update_command))
        assert_equal("id=100,name='Joe Blow'", foo01.send(:attributes_for_update_command, include_primary_key: true))
      end

      def test_attribute_names_for_create_command
        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        assert_equal("(id,name)", foo01.send(:attribute_names_for_create_command))
      end

      def test_attribute_values_for_create_command
        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        assert_equal("(100,'Joe Blow')", foo01.send(:attribute_values_for_create_command))
      end

      def test_exist_in_database?
        LiteOrm::Testing::Foo.ensure_table_exists!

        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        refute(foo01.send(:exist_in_database?))
        foo01.save!
        assert(foo01.send(:exist_in_database?))
      end

      def test_find_by_xxx
        LiteOrm::Testing::Foo.ensure_table_exists!

        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        foo02 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 101
          f.name = 'So Toyota'
        end

        foo01.save!
        foo02.save!

        assert_nil(LiteOrm::Testing::Foo.find_by_name('Jane Doe'))
        refute_nil(LiteOrm::Testing::Foo.find_by_name('Joe Blow'))

        assert_equal(100, LiteOrm::Testing::Foo.find_by_name('Joe Blow').id)
        assert_equal('Joe Blow', LiteOrm::Testing::Foo.find_by_name('Joe Blow').name)
      end

      def test_delete!
        LiteOrm::Testing::Foo.ensure_table_exists!

        foo01 = LiteOrm::Testing::Foo.new.tap do |f|
          f.id = 100
          f.name = 'Joe Blow'
        end

        refute(foo01.send(:exist_in_database?))
        foo01.save!
        assert(foo01.send(:exist_in_database?))
        foo01.delete!
        refute(foo01.send(:exist_in_database?))
      end

      def test_primary_key_is_text_type
        LiteOrm::Testing::Bar.ensure_table_exists!

        bar01 = LiteOrm::Testing::Bar.new.tap do |b|
          b.id_string = 'id 01'
          b.age = 54
        end

        refute(bar01.send(:exist_in_database?))
        bar01.save!
        assert(bar01.send(:exist_in_database?))
        bar01.age = 20
        bar01.save!

        bar02 = LiteOrm::Testing::Bar.find_by_id_string('id 01')
        refute_nil(bar02)
        bar02.delete!
        refute(bar02.send(:exist_in_database?))
        refute(bar02.send(:exist_in_database?))

      end
    end
  end
end
