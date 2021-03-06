require 'util/miq-password'

module FixAuth
  module AuthModel
    extend ActiveSupport::Concern

    module ClassMethods
      attr_accessor :password_columns

      def available_columns
        column_names & password_columns
      end

      def contenders(include_v2 = false)
        where(selection_criteria(include_v2))
      end

      # bring back anything with a password column that is not nil, blank, or v2:{.*}
      # include_v2 states that v2 encrypted passwords should come back too
      def selection_criteria(include_v2 = false)
        available_columns.collect do |column|
          col = ["COALESCE(#{column},'') <> ''"]
          col << "#{column} !~ 'v2:\{[^\}]*\}'" unless include_v2
          "(#{col.join(" AND ")})"
        end.join(" OR ")
      end

      def recrypt(old_value, options = {})
        if options[:hardcode]
          MiqPassword.encrypt(options[:hardcode])
        else
          MiqPassword.new.recrypt(old_value)
        end
      rescue
        if options[:invalid]
          MiqPassword.encrypt(options[:invalid])
        else
          raise
        end
      end

      def fix_passwords(obj, options = {})
        available_columns.each do |column|
          if (old_value = obj.send(column)).present?
            new_value = recrypt(old_value, options)
            obj.send("#{column}=", new_value) if new_value != old_value
          end
        end
        obj
      end

      def in_destination_format?(value)
        value.blank? || value =~ /^v2:\{.*\}$/
      end

      def display_record(r)
        puts "  #{r.id}:"
      end

      def display_column(r, column)
        if r.send("#{column}_changed?")
          puts "    #{column}: #{r.send("#{column}_was").inspect} => #{r.send(column).inspect} "
        elsif r.send(column).present?
          puts "    #{column}: #{r.send(column).inspect} (not changed)"
        end
      end

      def run(options = {})
        contenders(options[:v2]).each do |r|
          fix_passwords(r, options)
          if options[:verbose]
            display_record(r)
            available_columns.each do |column|
              display_column(r, column)
            end
          end
          r.save! unless options[:dry_run]
        end
      end

      def clean_up
        clear_active_connections!
      end
    end
  end
end
