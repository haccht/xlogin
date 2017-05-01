require 'net/ssh'
require 'xlogin/session'

module Xlogin
  class Ssh
    include Session

    def initialize(**opts)
      configure_session(opts.merge(port: opts[:port] || 22))

      begin
        username, password = *@userinfo

        @ssh = Net::SSH.start(
          @node,
          username,
          :port =>     @port,
          :timeout =>  @timeout,
          :password => password,
        )
      rescue TimeoutError
        raise TimeoutError, 'timed out while opening a connection to the host'
      rescue
        raise
      end

      @buf = ''
      @eof = false
      @channel = nil

      @ssh.open_channel do |channel|
        channel.on_data { |ch, data| @buf << data }
        channel.on_close { @eof = true }

        channel.request_pty do |ch, success|
          raise 'Failed to open ssh pty'   unless success
        end

        channel.send_channel_request('shell') do |ch, success|
          raise 'Failed to open ssh shell' unless success

          @channel = ch
          waitfor
          return
        end
      end

      @ssh.loop
    end

    def close
      @channel.close if @channel
      @ssh.close     if @ssh
    end

    def waitfor(opts = nil)
      time_out = @timeout
      waittime = @timeout

      case opts
      when Hash
        prompt   = if opts.has_key?('Match')
                     opts['Match']
                   elsif opts.has_key?('Prompt')
                     opts['Prompt']
                   elsif opts.has_key?('String')
                     Regexp.new( Regexp.quote(opts['String']) )
                   end
        time_out = opts['Timeout']  if opts.has_key?('Timeout')
        waittime = opts['Waittime'] if opts.has_key?('Waittime')
      else
        prompt = opts || Regexp.union(*@prompts.map(&:first))
      end

      buf  = ''
      rest = ''
      line = ''
      sock = @ssh.transport.socket

      until sock.available == 0 && @buf == "" && prompt != line && (@eof || (!sock.closed? && !IO::select([sock], nil, nil, waittime)))
        if  sock.available == 0 && @buf == "" && prompt !~ line && !IO::select([sock], nil, nil, time_out)
          raise Net::ReadTimeout, 'timed out while waiting for more data'
        end

        process_connection
        if @buf != ''
          buf  = rest + @buf
          rest = ''

          if pt = buf.rindex(/\r\z/no)
            buf  = buf[0...pt]
            rest = buf[pt..-1]
          end

          @buf = ''
          line += buf
          @logger.call(buf)
        elsif @eof
          break
        end
      end

      _, process = @prompts.find { |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += waitfor(opts)
      end
      line
    end

    def print(string)
      @channel.send_data(string)
      process_connection
    end

    def puts(string)
      print(string + "\n")
    end

    def cmd(opts)
      match    = Regexp.union(*@prompts.map(&:first))
      time_out = @timeout

      if opts.kind_of?(Hash)
        string   = opts['String']
        match    = opts['Match']   if opts.has_key?('Match')
        time_out = opts['Timeout'] if opts.has_key?('Timeout')
      else
        string = opts
      end

      puts(string)
      waitfor('Prompt' => match, 'Timeout' => time_out)
    end

    def interact!
      raise 'Not implemented'
    end

    private
    def process_connection
      begin
        @channel.connection.process(0)
      rescue IOError
        @eof = true
      end
    end

  end
end
