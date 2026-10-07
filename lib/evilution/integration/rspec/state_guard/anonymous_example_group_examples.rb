# frozen_string_literal: true

require_relative "../state_guard"
require_relative "../../rspec"

# Drops the examples a run registers on RSpec::Core::AnonymousExampleGroup
# (GH #1765).
#
# Example#initialize appends every example to its group's `examples`. Most
# groups are thrown away with the run, but AnonymousExampleGroup is a constant:
# whatever lands there stays for the life of the process. A run with a suite
# hook puts a SuiteHookContext there, and the reporter notifying a non-example
# exception puts an Example there. Each holds that run's reporter, and the
# reporter holds every example the run loaded, so one in-process run after
# another retained them all, about 1 MB per mutation on the memory_check
# fixture.
#
# Forked runs never leak this (the child dies), only the in-process path.
class Evilution::Integration::RSpec::StateGuard::AnonymousExampleGroupExamples
  def snapshot
    examples&.length
  end

  def release(length)
    return unless length

    examples&.slice!(length..)
  end

  private

  def examples
    return nil unless defined?(::RSpec::Core::AnonymousExampleGroup)

    ::RSpec::Core::AnonymousExampleGroup.examples
  end
end
