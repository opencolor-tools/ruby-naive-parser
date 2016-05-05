# A naive, line based approach to parsing OCO

## Rationale

Fiddling with the grammar is incredibly time consuming and small changes often result in side effects and thus take a lot more time than estimated.

I am entirely sure that this is my fault. Or rather: I just don't know enough about the construction of robust lexers and parsers to get a malleable and robust end result.

For the sake of the project, I think it is reasonable to try out a more naive approach. The reason I'm trying this in Ruby is just to feel that little bit more comfortable
with both the language and the testing tools to reach greater speed. I suspect, though, that porting this back to JavaScript should still be a rather trivial task.

## Approach

In contrast to the grammar based approach, this parser tries to simply attack the whole thing on a strict line by line basis. I'm doing it in three steps, which are kind of similar to the the steps in the grammar based approach but work completely different:

1. Tokenize the lines by splitting by colon and stripping extra whitespace (this is somewhat similar to the lexer step) and recording the indent level
2. Try to parse these tokenized lines into a meaningful tree structure. (this would be analogous to the parser step, but is probably the most naive part)
3. Adjust the types of the tree nodes accordingly to the syntax rules. This step is (with one exception) also responsible for all the error checking.

## Benefits

* The naive approach means that it is much easier to be relaxed about the syntax.
* Having all the parsing in simple code means that it's much easier (for me at least) to debug parser problems. There's no "black box" (the compiled parser code) in the code base anymore.
* It's much easier to find the right places to record and report errors and supply meaningful error messages

## Usage

I'll add real tests soon. Right now you can call the "test" from the command line:

    $ ruby parse.rb test/fixtures/test_with_comments.oco

This will output a structure that is probably similar to an AST. conversion to a tree of meaningful objects is currently missing.
