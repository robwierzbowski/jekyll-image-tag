# Title: Jekyll Image Tag
# Authors: Rob Wierzbowski : @robwierzbowski
#
# Description: Better images for Jekyll.
#
# Download: https://github.com/robwierzbowski/jekyll-image-tag
# Documentation: https://github.com/robwierzbowski/jekyll-image-tag/readme.md
# Issues: https://github.com/robwierzbowski/jekyll-image-tag/issues
#
# Syntax:  {% image [preset or WxH] path/to/img.jpg [attr="value"] %}
# Example: {% image poster.jpg alt="The strange case of Dr. Jekyll" %}
#          {% image gallery poster.jpg alt="The strange case of Dr. Jekyll" class="gal-img" data-selected %}
#          {% image 350xAUTO poster.jpg alt="The strange case of Dr. Jekyll" class="gal-img" data-selected %}
#
# See the documentation for full configuration and usage instructions.

require 'fileutils'
require 'pathname'
require 'digest/md5'
require 'mini_magick'

module Jekyll

  class Image < Liquid::Tag

    def initialize(tag_name, markup, tokens)
      @markup = markup
      super
    end

    def render(context)

      # Render any liquid variables in tag arguments and unescape template code
      render_markup = Liquid::Template.parse(@markup).render(context).gsub(/\\\{\\\{|\\\{\\%/, '\{\{' => '{{', '\{\%' => '{%')

      # Gather settings
      site = context.registers[:site]
      settings = site.config['image']
      markup = /^(?:(?<preset>[^\s.:\/]+)\s+)?(?<image_src>[^\s]+\.[a-zA-Z0-9]{3,4})\s*(?<html_attr>[\s\S]+)?$/.match(render_markup)
      preset = settings['presets'][ markup[:preset] ]

      raise "Image Tag can't read this tag. Try {% image [preset or WxH] path/to/img.jpg [attr=\"value\"] %}." unless markup

      # Assign defaults
      settings['source'] ||= '.'
      settings['output'] ||= 'generated'

      # Prevent Jekyll from erasing our generated files
      site.config['keep_files'] << settings['output'] unless site.config['keep_files'].include?(settings['output'])

      # Process instance
      instance = if preset
        {
          :width => preset['width'],
          :height => preset['height'],
          :src => markup[:image_src]
        }
      elsif dim = /^(?:(?<width>\d+)|auto)(?:x)(?:(?<height>\d+)|auto)$/i.match(markup[:preset])
        {
          :width => dim['width'],
          :height => dim['height'],
          :src => markup[:image_src]
        }
      else
        { :src => markup[:image_src] }
      end

      # Process html attributes
      html_attr = if markup[:html_attr]
        Hash[ *markup[:html_attr].scan(/(?<attr>[^\s="]+)(?:="(?<value>[^"]+)")?\s?/).flatten ]
      else
        {}
      end

      if preset && preset['attr']
        html_attr = preset['attr'].merge(html_attr)
      end

      html_attr_string = html_attr.inject('') { |string, attrs|
        if attrs[1]
          string << "#{attrs[0]}=\"#{attrs[1]}\" "
        else
          string << "#{attrs[0]} "
        end
      }

      # Raise some exceptions before we start expensive processing
      raise "Image Tag can't find the \"#{markup[:preset]}\" preset. Check image: presets in _config.yml for a list of presets." unless preset || dim ||  markup[:preset].nil?

      # Generate resized images
      generated_src = generate_image(instance, site.source, site.dest, settings['source'], settings['output'])
      unless generated_src
        return
      end

      generated_src = File.join(site.baseurl, generated_src) unless site.baseurl.empty?
      # Return the markup!
      "<img src=\"#{generated_src}\" #{html_attr_string}>"
    end

    def generate_image(instance, site_source, site_dest, image_source, image_dest)

      image_source_path = File.join(site_source, image_source, instance[:src])
      unless File.exists?image_source_path
        puts "Missing: #{image_source_path}"
        return false
      end

      image = MiniMagick::Image.open(image_source_path)
      image.coalesce
      digest = Digest::MD5.hexdigest(image.to_blob).slice!(0..5)

      image_dir = File.dirname(instance[:src])
      ext = File.extname(instance[:src])
      basename = File.basename(instance[:src], ext)

      orig_width = image[:width].to_f
      orig_height = image[:height].to_f
      orig_ratio = orig_width/orig_height

      gen_width = if instance[:width]
        instance[:width].to_f
      elsif instance[:height]
        orig_ratio * instance[:height].to_f
      else
        orig_width
      end
      gen_height = if instance[:height]
        instance[:height].to_f
      elsif instance[:width]
        instance[:width].to_f / orig_ratio
      else
        orig_height
      end
      gen_ratio = gen_width/gen_height

      # Don't allow upscaling. If the image is smaller than the requested dimensions, recalculate.
      if orig_width < gen_width || orig_height < gen_height
        undersize = true
        gen_width = if orig_ratio < gen_ratio then orig_width else orig_height * gen_ratio end
        gen_height = if orig_ratio > gen_ratio then orig_height else orig_width/gen_ratio end
      end

      gen_name = "#{basename}-#{gen_width.round}x#{gen_height.round}-#{digest}#{ext}"
      gen_dest_dir = File.join(site_dest, image_dest, image_dir)
      gen_dest_file = File.join(gen_dest_dir, gen_name)

      # Generate resized files
      unless File.exists?(gen_dest_file)

        warn "Warning:".yellow + " #{instance[:src]} is smaller than the requested output file. It will be resized without upscaling." if undersize

        #  If the destination directory doesn't exist, create it
        FileUtils.mkdir_p(gen_dest_dir) unless File.exist?(gen_dest_dir)

        # Let people know their images are being generated
        puts "Generating #{gen_name}"

        # Scale and crop
        image.combine_options do |i|
          i.resize "#{gen_width}x#{gen_height}^"
          i.gravity "center"
          i.crop "#{gen_width}x#{gen_height}+0+0"
          i.layers "Optimize"
        end

        image.write gen_dest_file
      end

      # Return path relative to the site root for html
      Pathname.new(File.join('/', image_dest, image_dir, gen_name)).cleanpath
    end
  end
end

Liquid::Template.register_tag('image', Jekyll::Image)
