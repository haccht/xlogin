require 'thread'
require 'timeout'

module Xlogin
  module Session
    def thread_safe(timeout: @timeout, maximum_retry: 1)
      @safe_session = self
      @safe_session_mutex ||= Mutex.new

      Timeout.timeout(timeout) do
        @safe_session_mutex.synchronize do
          retry_count = 0
          begin
            @safe_session ||= Xlogin.get(@host, @opts)
            yield @safe_session
          rescue Errno::ECONNRESET => e
            raise e unless (retry_count += 1) < maximum_retry
            @safe_session = nil
            retry
          end
        end
      end
    end
  end
end
