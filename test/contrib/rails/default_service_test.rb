require 'helper'

require 'contrib/rails/test_helper'

class TracingControllerTest < ActionController::TestCase
  setup do
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  test 'test that a lone span will have rails service picked up' do
    # Manually creating the span and forgetting service on purpose
    @tracer.trace('web.request') do |span|
      span.resource = '/index'
    end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[0]
    assert_equal('web.request', span.name)
    assert_equal('/index', span.resource, '/index')
    assert_equal('rake_test_loader', span.service) # [TODO:christian] fix this test, this should be rails-app
  end
end
