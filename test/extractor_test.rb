# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/slim_lang/extractor"

module RubyLsp
  module SlimLang
    class ExtractorTest < Minitest::Test
      def test_control_code
        assert_extracts(<<~SLIM, <<~RUBY)
          - user = current_user
          -  greet(user)
        SLIM
         |  user = current_user
         |   greet(user)
        RUBY
      end

      def test_output
        assert_extracts(<<~SLIM, <<~RUBY)
          = render(user)
          == raw(html)
          =>  spaced
        SLIM
         |  render(user)
         |   raw(html)
         |    spaced
        RUBY
      end

      def test_tag_output
        assert_extracts(<<~SLIM, <<~RUBY)
          h1 = title
          h1= title
          h1.title#main == raw(title)
        SLIM
         |     title
         |    title
         |                 raw(title)
        RUBY
      end

      def test_broken_lines
        assert_extracts(<<~SLIM, <<~RUBY)
          = link_to(name,
              path)
          - total = 1 + \\
            2
        SLIM
         |  link_to(name,
         |    path)
         |  total = 1 + \\
         |  2
        RUBY
      end

      def test_attribute_values
        assert_extracts(<<~SLIM, <<~RUBY)
          a href=user_path(user) Profile
          a(href=root_path) Home
          div *attributes_for(user)
        SLIM
         |       user_path(user)
         |       root_path
         |     attributes_for(user)
        RUBY
      end

      def test_ruby_block
        assert_extracts(<<~SLIM, <<~RUBY)
          ruby:
            greeting = Greeter.new(user)

            name = greeting.name
          p Hello
        SLIM
         |
         |  greeting = Greeter.new(user)
         |
         |  name = greeting.name
         |
        RUBY
      end

      def test_markup_is_blank
        assert_extracts(<<~SLIM, <<~RUBY)
          doctype html
          html
            / a comment
            body
              p Some text
              | More text
        SLIM
         |
         |
         |
         |
         |
         |
        RUBY
      end

      private

      def assert_extracts(template, expected)
        actual = Extractor.extract(template)

        assert_equal(
          expected.lines.map { |line| line.chomp.sub(/\A *\|/, "").rstrip },
          actual.lines.map(&:rstrip),
        )
        assert_positions_preserved(template, actual)
      end

      def assert_positions_preserved(template, actual)
        template_lines = template.lines
        actual.lines.each_with_index do |line, lineno|
          line.chomp.each_char.with_index do |char, col|
            next if char == " " || col >= template_lines[lineno].chomp.size

            assert_equal(template_lines[lineno][col], char, "moved from #{lineno + 1}:#{col}")
          end
        end
      end
    end
  end
end
