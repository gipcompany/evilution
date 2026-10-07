# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/anonymous_example_group_examples"

RSpec.describe Evilution::Integration::RSpec::StateGuard::AnonymousExampleGroupExamples do
  let(:strategy) { described_class.new }
  let(:examples) { RSpec::Core::AnonymousExampleGroup.examples }

  around do |example|
    saved = examples.dup
    example.run
  ensure
    examples.replace(saved)
  end

  it "snapshot returns the number of examples registered on AnonymousExampleGroup" do
    examples.push(:pre_a, :pre_b)

    expect(strategy.snapshot).to eq(examples.length)
  end

  it "release drops the examples registered after the snapshot" do
    examples.push(:pre)
    snap = strategy.snapshot
    examples.push(:added_a, :added_b)

    strategy.release(snap)

    expect(examples.last).to eq(:pre)
    expect(examples.length).to eq(snap)
  end

  it "release leaves the array alone when nothing was added" do
    examples.push(:pre)
    snap = strategy.snapshot

    strategy.release(snap)

    expect(examples.last).to eq(:pre)
    expect(examples.length).to eq(snap)
  end

  it "release is a no-op when snapshot is nil" do
    examples.push(:a)
    before = examples.length

    expect { strategy.release(nil) }.not_to raise_error
    expect(examples.length).to eq(before)
  end

  context "when RSpec::Core::AnonymousExampleGroup is not defined" do
    before { hide_const("RSpec::Core::AnonymousExampleGroup") }

    it "snapshot returns nil" do
      expect(strategy.snapshot).to be_nil
    end

    it "release is a no-op" do
      expect { strategy.release(0) }.not_to raise_error
    end
  end

  # The leak this strategy exists for: every run with a suite hook
  # registers a SuiteHookContext on AnonymousExampleGroup, and each one holds
  # that run's reporter and through it every example the run loaded.
  it "releases the SuiteHookContext a run with a suite hook registers" do
    snap = strategy.snapshot
    RSpec::Core::SuiteHookContext.new("before(:suite) hook", RSpec::Core::NullReporter)

    expect { strategy.release(snap) }.to change(examples, :length).by(-1)
  end
end
