# frozen_string_literal: true

require "test_helper"
require "prism"
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
         |       user_path(user);
         |       root_path;
         |     attributes_for(user)
        RUBY
      end

      def test_fragments_on_one_line_are_separated
        assert_extracts(<<~SLIM, <<~RUBY)
          a href=user_path(user) title=user.name = user.nickname
        SLIM
         |       user_path(user);      user.name;  user.nickname
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

      def test_interpolation_in_text
        assert_extracts(<<~'SLIM', <<~RUBY)
          p Hello #{user.name}!
          | Hi #{a} and #{b}
          p
            | First line
              then #{c}
          <b>#{d}</b>
          /! Rendered #{e}
        SLIM
         |          user.name;
         |       a;       b;
         |
         |
         |           c;
         |     d;
         |              e;
        RUBY
      end

      def test_interpolation_in_quoted_attributes
        assert_extracts(<<~'SLIM', <<~RUBY)
          a href="/users/#{user.id}" title='#{user.name}' Profile
        SLIM
         |                 user.id;           user.name;
        RUBY
      end

      def test_interpolation_in_embedded_engines
        assert_extracts(<<~'SLIM', <<~RUBY)
          javascript:
            var user = #{user.to_json};
        SLIM
         |
         |               user.to_json;
        RUBY
      end

      def test_interpolation_with_nested_braces
        assert_extracts(<<~'SLIM', <<~RUBY)
          p #{items.map { |i| i.name }.join}
        SLIM
         |    items.map { |i| i.name }.join;
        RUBY
      end

      def test_unescaped_interpolation
        assert_extracts(<<~'SLIM', <<~RUBY)
          p #{{raw_html}}
        SLIM
         |     raw_html;
        RUBY
      end

      def test_text_that_is_not_interpolated
        assert_extracts(<<~'SLIM', <<~RUBY)
          p Escaped \#{not_ruby}
          / A Slim comment #{not_rendered}
        SLIM
         |
         |
        RUBY
      end

      def test_implicit_ends
        assert_extracts(<<~SLIM, <<~RUBY)
          - if admin?
            p Admin
          - elsif user
            p User
          - else
            p Guest
          ul
            - items.each do |item|
              li = item.name
          = form_with(model: user) do |form|
            = form.text_field(:name)
        SLIM
         |  if admin?
         |
         |  elsif user
         |
         |  else
         |         ;end
         |
         |    items.each do |item|
         |         item.name;end
         |  form_with(model: user) do |form|
         |    form.text_field(:name);end
        RUBY
      end

      def test_implicit_ends_for_nested_blocks
        assert_extracts(<<~SLIM, <<~RUBY)
          - users.each do |user|
            - if user.admin?
              p Admin

          p After
        SLIM
         |  users.each do |user|
         |    if user.admin?
         |           ;end;end
         |
         |
        RUBY
      end

      def test_implicit_ends_for_case
        assert_extracts(<<~SLIM, <<~RUBY)
          - case role
          - when :admin
            p Admin
          - when :user
            p User
          p After
        SLIM
         |  case role
         |  when :admin
         |
         |  when :user
         |        ;end
         |
        RUBY
      end

      def test_comments_do_not_hide_implicit_ends
        assert_extracts(<<~'SLIM', <<~'RUBY')
          - if admin? # admins only
            = link_to(name, path) # a link
          - items.each do |item|
            = "#{item.name} # not a comment"
        SLIM
         |  if admin? # admins only
         |    link_to(name, path)         ;end
         |  items.each do |item|
         |    "#{item.name} # not a comment";end
        RUBY
      end

      def test_implicit_ends_after_a_heredoc
        assert_extracts(<<~SLIM, <<~RUBY)
          - if admin?
            ruby:
              note = <<~TEXT
                Hello
              TEXT
          p = note
          - if guest?
            ruby:
              note = <<~TEXT
                Hello
              TEXT
          = note
        SLIM
         |  if admin?
         |
         |    note = <<~TEXT
         |      Hello
         |    TEXT
         |end;note
         |  if guest?
         |
         |    note = <<~TEXT
         |      Hello
         |    TEXT
         |  note;end
        RUBY
      end

      def test_implicit_ends_after_a_heredoc_with_no_ruby_below_it
        assert_extracts(<<~SLIM, <<~RUBY)
          - if admin?
            ruby:
              note = <<~TEXT
                Hello
              TEXT

          p Text
        SLIM
         |  if admin?
         |
         |    note = <<~TEXT
         |      Hello
         |    TEXT
         |;end
         |
        RUBY
        assert_extracts(<<~SLIM, <<~RUBY)
          - if admin?
            ruby:
              note = <<~TEXT
                Hello
              TEXT
          p
        SLIM
         |  if admin?
         |
         |    note = <<~TEXT
         |      Hello
         |    TEXT
         | ;end
        RUBY

        extracted = Extractor.extract("- if admin?\n  ruby:\n    note = <<~TEXT\n      Hello\n    TEXT")
        assert_equal(["    TEXT", ";end"], extracted.lines.last(2).map(&:chomp))
        assert_empty(Prism.parse(extracted, partial_script: true).errors)
      end

      def test_skips_statements_slim_cannot_parse
        assert_extracts(<<~SLIM, <<~RUBY)
          p = before
          a(href=unclosed
          %p Unknown line indicator
          p = after
        SLIM
         |    before
         |
         |
         |    after
        RUBY
      end

      def test_keeps_the_lines_nested_under_a_skipped_statement
        assert_extracts(<<~SLIM, <<~RUBY)
          doctype html
          html(lang=
            body
              p = first
              p = second
        SLIM
         |
         |
         |
         |        first
         |        second
        RUBY
      end

      def test_blanks_a_skipped_statement_that_cannot_have_a_parent
        assert_extracts(<<~SLIM, <<~RUBY)
          img/
            p = orphan
          p = after
        SLIM
         |
         |
         |    after
        RUBY
      end

      def test_keeps_ruby_found_before_too_many_errors
        template = "p = before\n" + "%p\n" * (Extractor::MAX_SKIPPED_STATEMENTS + 1) + "p = after\n"

        assert_equal("    before", Extractor.extract(template).lines.first.rstrip)
        refute_includes(Extractor.extract(template), "after")
      end

      def test_blanks_take_the_width_of_what_they_replace
        template = 'p 😀 é #{user.name}'

        assert_equal("         user.name;", Extractor.extract(template))
        assert_equal("            user.name;", Extractor.extract(template, encoding: Encoding::UTF_8))
        assert_equal("        user.name;", Extractor.extract(template, encoding: Encoding::UTF_32))
      end

      def test_binary_and_invalid_source
        extracted = Extractor.extract("p = café\n= total \xFF".b)

        assert_equal(["    café", "  total \u{FFFD}"], extracted.lines.map(&:rstrip))
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
        assert_empty(Prism.parse(actual, partial_script: true).errors.map(&:message))
      end

      def assert_positions_preserved(template, actual)
        template_lines = template.lines
        actual.lines.each_with_index do |line, lineno|
          moved_ends = line[/\A(?:end;)*/].size
          line.chomp.each_char.with_index do |char, col|
            next if [" ", ";"].include?(char) || col < moved_ends || col >= template_lines[lineno].chomp.size

            assert_equal(template_lines[lineno][col], char, "moved from #{lineno + 1}:#{col}")
          end
        end
      end
    end
  end
end
