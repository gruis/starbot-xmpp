# Monkey patch to fix the REXML's failure of parsing XML that xmpp servers send.
# As a result of this bug, bot fails to join some chatroom with encoding error.
# The monkey patching is acceptable since xmpp4r is no longer maintained.
#
# See https://github.com/lnussbaum/xmpp4r/issues/3
#
require 'socket'
class TCPSocket
  def external_encoding
    Encoding::BINARY
  end
end

require 'rexml/source'
class REXML::IOSource
  alias_method :encoding_assign, :encoding=
  def encoding=(value)
    encoding_assign(value) if value
  end
end

begin
  # OpenSSL is optional and can be missing
  require 'openssl'
  class OpenSSL::SSL::SSLSocket
    def external_encoding
      Encoding::BINARY
    end
  end
rescue
end