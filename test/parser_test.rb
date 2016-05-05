require 'test_helper'
require 'parser'
require 'pp'

class ParserTest < MiniTest::Test
  def test_simple_group
    input = <<-END
    group:
      color: #f00
    END
    p = Parser.parse(StringIO.new(input))
    assert_equal '#f00', p['group']['color']['rgb'].value
    assert_equal '#f00', p['group']['color'].hexcolor
  end

end
