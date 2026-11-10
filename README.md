# ruby-lsp-slim-lang

A [Ruby LSP](https://github.com/Shopify/ruby-lsp) add-on for the Ruby inside [Slim](https://slim-template.github.io)
templates. It gives you go-to-definition, hover, completion and the other features Ruby LSP offers for ERB, in `.slim`
files.

Since it reads templates with Slim's own parser, it understands Slim's syntax the way Slim does. That includes attribute
values, splats, `ruby:` blocks, `#{}` interpolation and lines continued with a trailing comma or backslash.

## Installation

Since Ruby LSP only loads add-ons from your application's bundle, add the gem to its `Gemfile`, next to `slim`.

```ruby
group :development do
  gem "ruby-lsp-slim-lang", require: false
end
```

Then restart Ruby LSP.

### Neovim

Add `slim` to the file types Ruby LSP is attached to. With Neovim 0.11 and `nvim-lspconfig`:

```lua
vim.lsp.config("ruby_lsp", {
  filetypes = { "ruby", "eruby", "slim" },
})
vim.lsp.enable("ruby_lsp")
```

Or, with older versions of `nvim-lspconfig`:

```lua
require("lspconfig").ruby_lsp.setup({
  filetypes = { "ruby", "eruby", "slim" },
})
```

Neovim 0.10 doesn't detect `.slim` files by itself, and other versions haven't been checked. If yours doesn't, and you
don't have a Slim syntax plugin, add:

```lua
vim.filetype.add({ extension = { slim = "slim" } })
```

### VS Code

The Ruby LSP extension only sends Ruby and ERB files to the server. It has no setting to send other languages, so VS
Code isn't supported for now.

## What to expect

Features behave the way they do in ERB templates, since Ruby LSP treats a Slim template as one.

- Calls without a receiver, such as helpers, resolve to any indexed method with that name.
- Since Ruby LSP can't tell what a controller assigns to an instance variable, calls on it also fall back to matching
  by name.
- Diagnostics, formatting and rename aren't available, as they aren't for ERB either.

Some things are specific to Slim:

- If Slim can't parse part of a template, ruby-lsp-slim-lang skips the line the failing statement starts on and reads
  the rest. Until you fix the error, that line gets no features.
- Since Ruby LSP doesn't boot your application, ruby-lsp-slim-lang only knows Slim's default shortcuts and attribute
  delimiters. It won't recognise any you configure, for example in an initialiser.

## Development

```sh
bundle install
bundle exec rake
```
