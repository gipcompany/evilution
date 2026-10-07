# frozen_string_literal: true

require_relative "../memory"

class Evilution::Memory::LeakCheck
  WARMUP_ITERATIONS = 5
  DEFAULT_ITERATIONS = 50
  DEFAULT_MAX_GROWTH_KB = 10_240 # 10 MB

  attr_reader :samples

  def initialize(iterations: DEFAULT_ITERATIONS, max_growth_kb: DEFAULT_MAX_GROWTH_KB,
                 warmup_iterations: WARMUP_ITERATIONS)
    @iterations = iterations
    @max_growth_kb = max_growth_kb
    @warmup_iterations = warmup_iterations
    @samples = []
  end

  def run(&)
    warmup(&)
    measure(&)
    result
  end

  def rss_available?
    !Evilution::Memory.rss_kb.nil?
  end

  def growth_kb
    return nil if samples.any?(&:nil?)
    return 0 if samples.size < 2

    samples.last - samples.first
  end

  # Growth from the first sample to the last, less the largest rise between two
  # consecutive samples (GH #2).
  #
  # RSS does not grow by the byte. The allocator takes memory in chunks, so a
  # workload that has stopped growing can still step up once, by several MB,
  # wherever the heap happens to cross a boundary, and that one step decided
  # the endpoint reading. A leak is not one step: it grows across the run, and
  # taking out its largest step leaves the rest of it.
  def sustained_growth_kb
    kb = growth_kb
    return kb if kb.nil? || samples.size < 2

    kb - [largest_step_kb, 0].max
  end

  def passed?
    kb = sustained_growth_kb
    return false if kb.nil?

    kb <= @max_growth_kb
  end

  private

  def largest_step_kb
    samples.each_cons(2).map { |before, after| after - before }.max
  end

  def warmup(&block)
    @warmup_iterations.times { block.call }
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end

  def measure(&)
    @samples << Evilution::Memory.rss_kb

    @iterations.times do |i|
      yield

      next unless ((i + 1) % sample_interval).zero?

      GC.start
      @samples << Evilution::Memory.rss_kb
    end

    take_final_sample
  end

  def take_final_sample
    return if (@iterations % sample_interval).zero?

    GC.start
    @samples << Evilution::Memory.rss_kb
  end

  def sample_interval
    @sample_interval ||= [@iterations / 10, 1].max
  end

  def result
    sustained_kb = sustained_growth_kb
    {
      passed: passed?,
      growth_kb: growth_kb,
      growth_mb: growth_kb ? growth_kb / 1024.0 : nil,
      sustained_growth_kb: sustained_kb,
      sustained_growth_mb: sustained_kb ? sustained_kb / 1024.0 : nil,
      samples: samples,
      iterations: @iterations,
      max_growth_kb: @max_growth_kb,
      rss_available: rss_available?
    }
  end
end
