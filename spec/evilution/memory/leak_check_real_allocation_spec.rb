# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "evilution/memory/leak_check"

# The synthetic series in leak_check_spec.rb pin the arithmetic; these check
# the judgment against what RSS actually does when a block keeps, or
# drops, about 200 KB per iteration. Same parameters as the memory_check
# per-mutation check: 100 iterations against a 10 MB budget, so a 200 KB leak
# grows about 20 MB.
#
# Each check runs in a fresh Ruby, as memory_check does. Inside the suite the
# process holds memory earlier examples freed, still counted in RSS: a leak
# fills that first and RSS stays flat until it runs out, so the reading
# depends on which examples ran before.
RSpec.describe Evilution::Memory::LeakCheck, "on real allocations", if: File.exist?("/proc/self/status") do
  let(:lib_dir) { File.expand_path("../../../lib", __dir__) }

  def run_check(block_source)
    script = <<~RUBY
      require "json"
      require "evilution"
      require "evilution/memory/leak_check"

      retained = []
      result = Evilution::Memory::LeakCheck.new(iterations: 100, max_growth_kb: 10_240).run { #{block_source} }
      puts JSON.generate(result)
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib_dir, "-e", script)
    raise "leak check subprocess failed: #{err}" unless status.success?

    JSON.parse(out, symbolize_names: true)
  end

  it "fails a block that retains about 200 KB per iteration" do
    result = run_check('retained << ("x" * 204_800)')

    expect(result[:passed]).to be(false), "sustained growth #{result[:sustained_growth_kb]} KB, samples #{result[:samples]}"
  end

  it "passes a block that allocates as much but retains nothing" do
    result = run_check('"x" * 204_800')

    expect(result[:passed]).to be(true), "sustained growth #{result[:sustained_growth_kb]} KB, samples #{result[:samples]}"
  end
end
