class ParserError < StandardError
  def initialize(error, line, filename=nil)
    super(error)
    @message = error
    @line = line
    if line
      set_stacktrace("#{file || 'String'}:#{line + 1}")
    end
  end

  def to_str
    "#{@message}" + line ? "on line #{line + 1}" : ""
  end
end
class Metaproxy
  def initialize(data, hash)
    @data = data
    @hash = hash
    @fallbacks = []
  end
  def [](key)
    result = if (key.is_a?(Integer))
      @data[key]
    else
      @hash[key]
    end
    if result.nil?
      @fallbacks.each do |fallback|
        fr = fallback[key]
        return fr if fr
      end
    end
    return result
  rescue TypeError
    nil
  end
  def []=(key, value)
    md = Metadata.new(key, value)
    @data << md
    @hash[key] = md
  end
  def add_fallback(fallback)
    @fallbacks << fallback
  end
end

class Entry
  attr_reader :name, :line
  attr_accessor :parent
  def initialize(name, line = nil)
    @name = name
    @parent = nil
    @line = line
    @children = []
    @child_keys = {}
    @metadata = []
    @meta_keys = {}
  end

  def [](key)
    if (key.is_a?(Integer))
      @children[key]
    else
      @child_keys[key]
    end
  rescue TypeError
    nil
  end

  def metadata
    @metaproxy ||= Metaproxy.new(@metadata, @meta_keys)
  end

  def children=(children)
    @children = children || []
    @children.each do |child|
      child.parent = self
      @child_keys[child.name] = child
    end
  end
  def metadata=(metadata)
    @metadata = metadata || []
    @metadata.each do |datum|
      datum.parent = self
      @meta_keys[datum.name] = datum
    end
  end
end

class Metadata < Entry
  attr_reader :value
  def initialize(name, value, line = nil)
    super(name, line)
    @value = convert_meta_types(value)
  end
  def convert_meta_types(value)
    if value.downcase == 'true' || value.downcase == 'yes'
      true
    elsif value.match(/^[0-9]+$/)
      value.to_i
    elsif value.match(/^[0-9.]+$/)
      value.to_f
    elsif value.match(/^#[a-f0-9]{3,8}$/i) || value.match(/(^\w+)\(.*?\)$/)
      cv = ColorValue.new(value, line)
      cv.parent = self
      cv
    elsif value.match(/^=/)
      ref = Reference.new(nil, value, line)
      ref.parent = self # this is a hack to fix resolving
      ref
    else
      value
    end
  end
end

class Palette < Entry
  attr_reader :children
  def initialize(name, line = nil)
    super(name, line)
  end
  def <<(child)
    @children << child
    @child_keys[child.name] = child
  end
end

class Color < Entry
  attr_reader :color_values
  def initialize(name, line = nil)
    super(name, line)
  end
  def hexcolor()
    rgb = (self['rgb'] || self['rgba'])
    rgb ? rgb.value : nil
  end
end

class ColorValue < Entry
  attr_reader :value
  def initialize(value, line = nil)
    hex = value.match(/^#([a-f0-9]{3,8})$/i)
    other = value.match(/(^\w+)\(.*?\)$/)
    name = if hex
      if hex[1].length == 3 || hex[1].length == 6
        'rgb'
      elsif hex[1].length == 4 || hex[1].length == 8
        'rgba'
      else
        raise(ParserError.new("Malformed Hexcolor value", line))
      end
    elsif other
      other[1]
    else
      raise(ParserError.new("Invalid color value", line))
    end
    super(name, line)
    @value = value
  end
end

class Reference < Entry
  attr_reader :path
  def initialize(name, ref, line = nil)
    super(name, line)
    pathmatch = ref.match(/^=(.*)$/)
    if pathmatch
      @path = pathmatch[1]
    else
      raise(ParserError.new("Invalid reference value", line))
    end
  end
  def resolved(stack = [])
    path_parts = @path.split(".").map(&:strip)
    reference = resolve(parent, path_parts)
    if reference
      if reference.respond_to?(:path)
        return reference.resolved(stack + [self])
      else
        return reference
      end
    end
    nil
  end

  def resolve(current, path, notUp = false)
    resolved = current[path[0]]
    if resolved
      if path.length > 1
        resolved = resolve(resolved, path.drop(1), true)
      end
      if resolved
        return resolved
      end
    end
    if current.parent && !notUp
      return resolve(current.parent, path)
    else
      return null
    end
  end

  def metadata
    @metaproxy ||= begin
      meta = super()
      meta.add_fallback(resolved.metadata) if resolved.metadata
      meta
    end
  end



end

class Parser
  def self.parse(io)
    Parser.new(io).parse
  end

  def initialize(io)
    @io = io
  end

  def parse
    tokenized = tokenize(@io)
    transformed = transform(tokenized)
    adjusted = adjust_types(transformed)
    metaadjusted = normalize_metadata(adjusted)
    objectified = objectify(metaadjusted)
    return objectified
  end

  def tokenize(io)
    output = []
    io.each_line do |line|
      line = line.gsub(/\/\/.*$/, '') # remove comments
      tokens = line.split(':').map(&:strip)
      output.push(indent: indent(line), tokens: tokens)
    end
    return output
  end

  def indent(line)
    a = line.match(/^[ \t]+/)
    return 0 if a.nil?
    return a[0].length
  end

  def transform(tokenized)
    output = {children: [], type: 'root', name: 'root', parent: nil, line: 0}
    current_indent = tokenized[0][:indent]
    current_group = output
    tokenized.each_with_index do |line, i|
      next if line[:tokens].length == 1 && line[:tokens][0] == '' # remove empty lines from the stream
      if line[:indent] > current_indent
        current_indent = line[:indent]
        current_group = current_group[:children].last
      elsif line[:indent] < current_indent
        current_indent = line[:indent]
        current_group = current_group[:parent]
      end
      if line[:tokens].length == 2 && line[:tokens].last == '' # a group
        if line[:tokens].first.match(/\//)
          current_group[:children].push(type: 'metagroup', name: line[:tokens].first, parent: current_group, children: [], line: i)
        else
          current_group[:children].push(type: 'palette', name: line[:tokens].first, parent: current_group, children: [], line: i)
        end
      elsif line[:tokens].length == 1 # a color or a meta group with trailing slash
        if line[:tokens].first.match(/\/$/)
          current_group[:children].push(type: 'metagroup', name: line[:tokens].first, parent: current_group, children: [], line: i)
        elsif line[:tokens].first.match(/\//)
          raise(ParserError.new("A meta group must either have a trailing slash or must be closed with a colon", i))
        elsif line[:tokens].first.match(/^=/)
          current_group[:children].push(type: 'reference', value: line[:tokens].first, parent: current_group, children: [], line: i)
        else
          current_group[:children].push(type: 'colorvalue', value: line[:tokens].first, parent: current_group, children: [], line: i)
        end
      elsif line[:tokens].length == 2 # everything else is just a kv
        if line[:tokens].first.match(/\//)
          current_group[:children].push(type: 'metavalue', name: line[:tokens].first, value: line[:tokens].last, parent: current_group, children: [], line: i)
        else
          current_group[:children].push(type: 'value', name: line[:tokens].first, value: line[:tokens].last, parent: current_group, children: [], line: i)
        end
      else # other token lengths are syntax errors
        raise(ParseError.new("Too many colons", i))
      end
    end
    return output
  end

  def adjust_types(tree)
    tree[:children].each_with_index do |child, i|
      if child[:type] == 'palette'
        childtypes = child[:children].map{|c| c[:type] }.uniq
        if childtypes.include?('colorvalue')
          if childtypes.include?('palette')
            raise(ParserError.new("Color cannot contain both color values and a subpalette", child[:line]))
          elsif childtypes.include?('value')
            raise(ParserError.new("Color cannot contain both color values and named colors", child[:line]))
          end
          child[:type] = 'color'
        end
      elsif child[:type] == 'value'
        if child[:parent][:type] == 'metagroup'
          child[:type] = 'metavalue'
          check_for_children('Metavalue', child)
        else
          if child[:value].match(/^=/)
            child[:type] = 'reference'
          else
            child[:type] = 'color'
            child[:children].push(type: 'colorvalue', value: child[:value], parent: child, children: [], line: child[:line])
            child.delete(:value)
          end
        end
      elsif child[:type] == 'colorvalue'
        check_for_children('Colorvalue', child)
      end
      adjust_types(child)
    end
    tree
  end

  def check_for_children(type, obj)
    if obj[:children].length > 0
      raise(ParserError.new("#{type} #{obj[:name]} can't have children", obj[:line]))
    end
  end

  def normalize_metadata(tree)
    tree[:children].each_with_index do |child, i|
      normalize_metadata(child)
      if child[:type] == 'metavalue'
        if tree[:type] == 'metagroup'
          tree[:parent][:metadata] ||= []
          combined_name = [tree[:name], child[:name]].join('/').gsub(/\/\//, '/')
          add_metadata(tree[:parent], child, combined_name)
          tree[:children][i] = nil
        else
          add_metadata(tree, child)
          tree[:children][i] = nil
        end
      elsif child[:type] == 'metagroup'
        if child[:metadata]
          child[:metadata].each do |name, value|
            combined_name = [child[:name], name].join('/').gsub(/\/\//, '/')
            add_metadata(tree, child, combined_name)
          end
        end
        tree[:children][i] = nil
      end
    end
    tree[:children] = tree[:children].compact
    tree
  end

  def add_metadata(obj, metadata, name = nil)
    obj[:metadata] ||= []
    metadata[:name] = name if name
    metadata[:parent] = obj
    obj[:metadata] << metadata
  end

  def objectify(tree)
    children = tree[:children] || []
    children = children.map{|c| objectify(c)}

    if tree[:type] == 'root' || tree[:type] == 'palette'
      palette = Palette.new(tree[:name], tree[:line])
      palette.children = children
      metadata = tree[:metadata] || []
      palette.metadata = metadata.map {|md| Metadata.new(md[:name], md[:value], md[:line])}
      palette
    elsif tree[:type] == 'color'
      color = Color.new(tree[:name], tree[:line])
      color.children = children
      metadata = tree[:metadata] || []
      color.metadata = metadata.map {|md| Metadata.new(md[:name], md[:value], md[:line])}
      color
    elsif tree[:type] == 'colorvalue'
      cv = ColorValue.new(tree[:value], tree[:line])
      cv
    elsif tree[:type] == 'reference'
      ref = Reference.new(tree[:name], tree[:value], tree[:line])
      metadata = tree[:metadata] || []
      ref.metadata = metadata.map {|md| Metadata.new(md[:name], md[:value], md[:line])}
      ref
    end
  end

end
