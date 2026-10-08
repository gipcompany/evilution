# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::SplatOperator < Evilution::Mutator::Base
  def initialize(**options)
    super
    @exempt_splats = Set.new.compare_by_identity
  end

  def visit_splat_node(node)
    mutate_remove_splat(node) if node.expression && !@exempt_splats.include?(node)

    super
  end

  # A `**splat` inside a hash literal stays as written: dropping `**` from
  # `{ a: 1, **opts }` leaves a bare value among key-value pairs, which is a
  # syntax error.
  def visit_hash_node(node)
    node.elements.each { |el| @exempt_splats.add(el) }
    super
  end

  # The rest of a pattern binds what is left over; it is not a splat in a
  # call or a literal, so these splats are skipped. Dropping `**` from
  # `{ key:, **opts }` is a syntax error. Dropping `*` from `[a, *rest]`
  # parses, but it narrows the pattern to a fixed length. That mutant is
  # deliberately not emitted, and the pattern operators keep a binding rest
  # (`*rest`, `**opts`) as written. The rest of a multiple assignment
  # (`a, *b = x`) is still mutated: `a, b = x` parses and changes what `b`
  # binds.
  def visit_hash_pattern_node(node)
    @exempt_splats.add(node.rest) if node.rest
    super
  end

  def visit_array_pattern_node(node)
    @exempt_splats.add(node.rest) if node.rest
    super
  end

  def visit_find_pattern_node(node)
    @exempt_splats.add(node.left)
    @exempt_splats.add(node.right)
    super
  end

  # KeywordHashNode wraps call-arg kwargs + `**splat`. When an explicit
  # `k: v` or another `**splat` precedes a `**opts` splat in the same call,
  # demoting `**opts` to bare `opts` puts a positional after a keyword
  # argument and Ruby rejects it (`bar(k: v, opts)` and `bar(**a, opts)` are
  # syntax errors). Mark such splats so `visit_assoc_splat_node` skips them.
  # A splat that comes first (`bar(**opts, k: v)`) is still safe —
  # positional-before-keyword is fine.
  def visit_keyword_hash_node(node)
    node.elements.drop(1).each do |el|
      @exempt_splats.add(el) if el.is_a?(Prism::AssocSplatNode)
    end

    super
  end

  def visit_assoc_splat_node(node)
    return super if node.value.nil?
    return super if @exempt_splats.include?(node)

    mutate_remove_double_splat(node)

    super
  end

  private

  def mutate_remove_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.expression.slice,
      node: node
    )
  end

  def mutate_remove_double_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.value.slice,
      node: node
    )
  end
end
