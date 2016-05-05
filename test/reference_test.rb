require 'test_helper'
require 'parser'
require 'pp'

class ReferenceTest < MiniTest::Test
  def test_simple_color_reference
    input = <<-END
    group:
      color: #f00
    ref: =group.color
    END
    p = Parser.parse(StringIO.new(input))
    assert_equal '#f00', p['ref'].resolved.hexcolor
  end

  def test_group_reference
    input = <<-END
    group:
      oct/view: 'simple'
      oct/showValue: true
      color: #f00
    ref: =group
      oct/view: large
    END
    p = Parser.parse(StringIO.new(input))
    assert_equal '#f00', p['ref'].resolved['color'].hexcolor
  end

  def test_group_reference_with_meta_fallback
    input = <<-END
    group:
      oct/view: 'simple'
      oct/showValue: true
      color: #f00
    ref: =group
      oct/view: large
    END
    p = Parser.parse(StringIO.new(input))
    assert_equal 'large', p['ref'].metadata['oct/view'].value
    assert_equal true, p['ref'].metadata['oct/showValue'].value
  end

  def test_reference_in_metadata
    input = <<-END
    group:
      color: #f00
    other group:
      oct/backgroundColor: =group.color
    END
    p = Parser.parse(StringIO.new(input))
    assert_equal '#f00', p['other group'].metadata['oct/backgroundColor'].value.resolved.hexcolor
  end

end
