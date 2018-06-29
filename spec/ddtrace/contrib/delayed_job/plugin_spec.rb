require 'spec_helper'
require 'active_record'
require 'delayed_job'
require 'delayed_job_active_record'
require 'ddtrace'
require 'ddtrace/contrib/delayed_job/plugin'
require_relative 'active_record_setup'

SampleJob = Struct.new('SampleJob') { def perform; end }

RSpec.describe Datadog::Contrib::DelayedJob::Plugin, :delayed_job_active_record do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  before do
    logger = Logger.new(STDOUT)
    logger.level = Logger::WARN
  end

  before do
    Datadog.configure { |c| c.use :delayed_job, tracer: tracer }

    Delayed::Worker.delay_jobs = false
  end

  describe 'instrumenting worker execution' do
    let(:worker) { double(:worker, name: 'worker') }
    before do
      allow(tracer).to receive(:shutdown!).and_call_original
    end

    it 'execution callback yields control' do
      expect { |b| Delayed::Worker.lifecycle.run_callbacks(:execute, worker, &b) }.to yield_with_args(worker)
    end

    it 'shutdown happens after yielding' do
      Delayed::Worker.lifecycle.run_callbacks(:execute, worker) do
        expect(tracer).not_to have_received(:shutdown!)
      end

      expect(tracer).to have_received(:shutdown!)
    end
  end

  describe 'instrumented job invocation' do
    let(:job_params) { {} }
    subject(:job_run) { Delayed::Job.enqueue(SampleJob.new, job_params) }

    it 'creates a span' do
      expect { job_run }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    describe 'created span' do
      subject(:span) { tracer.writer.spans.first }

      before { job_run }

      it 'has service name taken from configuration' do
        expect(span.service).not_to be_nil
        expect(span.service).to eq(Datadog.configuration[:delayed_job][:service_name])
      end

      it 'has resource name equal to job name' do
        expect(span.resource).to eq(SampleJob.name)
      end

      it "span tags doesn't include queue name" do
        expect(span.get_tag('delayed_job.queue')).to be_nil
      end

      it 'span tags include job id' do
        expect(span.get_tag('delayed_job.id')).not_to be_nil
      end

      it 'span tags include priority' do
        expect(span.get_tag('delayed_job.priority')).not_to be_nil
      end

      it 'span tags include number of attempts' do
        expect(span.get_tag('delayed_job.attempts')).to eq('0')
      end

      context 'when queue name is set' do
        let(:queue_name) { 'queue_name' }
        let(:job_params) { { queue: queue_name } }

        it 'span tags include queue name' do
          expect(span.get_tag('delayed_job.queue')).to eq(queue_name)
        end
      end

      context 'when priority is set' do
        let(:priority) { 12345 }
        let(:job_params) { { priority: priority } }

        it 'span tags include job id' do
          expect(span.get_tag('delayed_job.priority')).to eq(priority.to_s)
        end
      end
    end
  end
end
