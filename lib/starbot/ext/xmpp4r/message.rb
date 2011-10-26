module Jabber
  class Message < XMPPStanza
    def invite?
      first_element("x") && !first_element("x").first_element("invite").nil?
    end # invite?
    def invite_from
      return nil unless invite?
      first_element("x").first_element("invite").attribute("from") && first_element("x").first_element("invite").attribute("from").value
    end # invite_from
  end # class::Message < XMPPStanza
end # module::Jabber