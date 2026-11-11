# ruby-lsp-slim-lang

A [Ruby LSP](https://github.com/Shopify/ruby-lsp) add-on for the Ruby inside [Slim](https://slim-template.github.io)
templates. It gives you go-to-definition, hover, completion and the other features Ruby LSP offers for ERB, in `.slim`
files.

Since it reads templates with Slim's own parser, it understands most of Slim's syntax the way Slim does. That includes
attribute values, splats, `ruby:` blocks, `#{}` interpolation and lines continued with a trailing comma or backslash.

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

Neovim doesn't detect `.slim` files by itself (as of 0.12). Unless a Slim syntax plugin does that for you, add:

```lua
vim.filetype.add({ extension = { slim = "slim" } })
```

### VS Code

The Ruby LSP extension only sends Ruby and ERB files to the server. I've opened
[Shopify/ruby-lsp#4270][vscode-pr] to add a `rubyLsp.addonLanguageIds` setting that sends other languages too. Until a
release of the extension includes it, you can build the extension from [my fork][vscode-fork]:

```sh
git clone --branch addon-language-ids https://github.com/bjeanes/ruby-lsp.git
cd ruby-lsp/vscode
pnpm install
pnpm run package
code --install-extension vscode-ruby-lsp.vsix
```

Since VS Code would otherwise replace it with the Marketplace version, turn off auto-update for the Ruby LSP extension.
You'll also need an extension that gives `.slim` files the `slim` language ID, such as a Slim syntax extension. Then add
this to your settings and reload the window:

```json
"rubyLsp.addonLanguageIds": ["slim"]
```

[vscode-pr]: https://github.com/Shopify/ruby-lsp/pull/4270
[vscode-fork]: https://github.com/bjeanes/ruby-lsp/tree/addon-language-ids

## What to expect

Features behave the way they do in ERB templates, since Ruby LSP treats a Slim template as one.

- Calls without a receiver, such as helpers, resolve to any indexed method with that name.
- Since Ruby LSP can't tell what a controller assigns to an instance variable, calls on it also fall back to matching
  by name.
- Diagnostics, formatting and rename aren't available, as they aren't for ERB either.

Some things are specific to Slim:

- If Slim can't parse part of a template, ruby-lsp-slim-lang skips the line the failing statement starts on and reads
  the rest. Until you fix the error, that line gets no features.
- Slim adds a `do` to a line such as `- 3.times` when lines are nested under it. ruby-lsp-slim-lang doesn't yet. Since
  that only changes the scope of local variables assigned in those lines, you're unlikely to notice.
- Since Ruby LSP doesn't boot your application, ruby-lsp-slim-lang only knows Slim's default shortcuts and attribute
  delimiters. It won't recognise any you configure, for example in an initialiser.

## Development

```sh
bundle install
bundle exec rake
```

## Licence

MIT. See [LICENSE.txt](LICENSE.txt).
