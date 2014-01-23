require "#{BASE}/libs/ContentGenerator.rb"

class HTMLGenerator < ContentGenerator
	def initialize(params)
		super(params)
	end

	def generate(parse_tree)
		pass1 = []
		pass2 = []

		parse_tree.each_with_index {|*piece_with_index|
			piece, index = piece_with_index

			if piece[:data]
				pass2 << piece_with_index
			else
				pass1 << piece_with_index
			end
		}

		pass1.each {|piece, index|
			processor = 'process_' + piece.keys[0].to_s
			result = self.send(processor, piece)
			parse_tree[index] = result
		}

		Parallel.map(pass2, :in_processes => 10) {|piece, index|
			processor = 'process_' + piece.keys[0].to_s
			[self.send(processor, piece), index]
		}.each {|result, index|
			parse_tree[index] = result
		}

		result = parse_tree.collect {|piece| piece[:text] ? piece[:text] : piece.inspect }.join
		return result
	end
end
