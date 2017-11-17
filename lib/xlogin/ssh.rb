require 'net/ssh/telnet'
require 'xlogin/session'

module Xlogin
  class Ssh < Net::SSH::Telnet

    prepend SessionModule

    def interact!
      raise 'Not implemented'
    end

  end
end
