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
    return adjusted
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
    output = {children: [], type: 'root', parent: nil, line: 0}
    current_indent = 0
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
      elsif line[:tokens].length == 1 # a color
        if line[:tokens].first.match(/\/$/)
          current_group[:children].push(type: 'metagroup', name: line[:tokens].first, parent: current_group, children: [], line: i)
        else
          pp [i, line[:tokens]]
          current_group[:children].push(type: 'colorvalue', value: line[:tokens].first, parent: current_group, children: [], line: i)
        end
      elsif line[:tokens].length == 2 # everything else is just a kv
        if line[:tokens].first.match(/\//)
          current_group[:children].push(type: 'metavalue', name: line[:tokens].first, value: line[:tokens].last, parent: current_group, children: [], line: i)
        else
          current_group[:children].push(type: 'value', name: line[:tokens].first, value: line[:tokens].last, parent: current_group, children: [], line: i)
        end
      else # other token lengths are syntax errors
        raise("Too many colons error on line #{i+1}")
      end
    end
    return output
  end

  def adjust_types(tree)
    tree[:children].each_with_index do |child, i|
      if child[:type] == 'palette'
        childtypes = child[:children].map{|c| c[:type] }.uniq
        if childtypes.include?('colorvalue')
          if childtypes.include?('group')
            raise("Color #{child[:name]} on line #{child[:line] + 1} contains both color values and palette, which is not allowed")
          elsif childtypes.include?('value')
            raise("Color #{child[:name]} on line #{child[:line] + 1} contains both color values and other named colors, which is not allowed")
          end
          child[:type] = 'color'
        end
      elsif child[:type] == 'value'
        if child[:parent][:type] == 'metagroup'
          child[:type] = 'metavalue'
          check_for_children('Metavalue', child)
        else
          child[:type] = 'color'
          child[:children].push(type: 'colorvalue', value: child[:value], parant: child, children: [], line: child[:line])
          child.delete(:value)
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
      pp obj
      raise("#{type} #{obj[:name]} on line #{obj[:line] + 1} can't have children")
    end
  end
end
