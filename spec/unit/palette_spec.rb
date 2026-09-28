require "spec_helper"
require "json"
require "digest"

RSpec.describe "Lospec500 color contract" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:palette) { JSON.parse(File.read(File.join(root, "config/palettes/lospec500.json"))).fetch("colors") }
  let(:css) { File.read(File.join(root, "app/assets/stylesheets/application.css")) }

  def luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map do |byte|
      channel = byte.to_i(16) / 255.0
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
    channels.zip([0.2126, 0.7152, 0.0722]).sum { |channel, weight| channel * weight }
  end

  def contrast(first, second)
    dark, light = [luminance(first), luminance(second)].sort
    (light + 0.05) / (dark + 0.05)
  end

  it "retains the exact published 42-color palette" do
    expect(palette.size).to eq(42)
    expect(palette.uniq.size).to eq(42)
    expect(palette).to all(match(/\A#[0-9a-f]{6}\z/))
    expect(Digest::SHA256.hexdigest(palette.join)).to eq("e46abea92d49e4d8acd1e24e1afaaa4e41899462a4ac442e303edc56fcadef55")
  end

  it "allows only palette literals in app-owned styles, scripts, templates and starter content" do
    paths = Dir[File.join(root, "app/**/*.{css,js,haml,rb}")].reject { |path| path.include?("/builds/") }
    paths.each do |path|
      content = File.read(path)
      content.scan(/(?<![\w-])#([\da-f]{8}|[\da-f]{6}|[\da-f]{4}|[\da-f]{3})\b/i).flatten.each do |hex|
        normalized = hex.size == 3 ? hex.chars.map { |char| char * 2 }.join : hex
        expect(palette).to include("##{normalized.downcase}"), "Off-palette color ##{hex} in #{path}"
      end
      expect(content).not_to match(/\b(?:rgb|rgba|hsl|hsla|oklch|oklab|color-mix|linear-gradient|radial-gradient)\(/i)
      expect(content).not_to match(/\bopacity\s*:\s*(?:0?\.\d|0\.[1-9])/)
      expect(content).not_to match(/\b(?:color|background|backgroundColor|fill|stroke)\s*:\s*["']?(?:black|red|blue|green|gray|grey|silver|orange|yellow|purple|pink|white)\b/i)
    end
    expect(css).to include("--color-*: initial")
  end

  it "keeps text readable on both theme surfaces and buttons" do
    themes = css.scan(/:root(?:\[data-theme="dark"\])?\s*\{([^}]+)\}/).flatten
    expect(themes.size).to eq(2)
    themes.each do |theme|
      tokens = theme.scan(/--([\w-]+):\s*(#[\da-f]{6})/).to_h
      %w[ink muted accent error syntax-string syntax-number].each do |foreground|
        %w[paper panel selection active-line match bracket].each do |background|
          expect(contrast(tokens.fetch(foreground), tokens.fetch(background))).to be >= 4.5
        end
      end
      expect(contrast(tokens.fetch("accent-ink"), tokens.fetch("accent"))).to be >= 4.5
      %w[paper panel].each { |surface| expect(contrast(tokens.fetch("line"), tokens.fetch(surface))).to be >= 3 }
    end
  end
end
