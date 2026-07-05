require "ipaddr"
require "resolv"

class WebhookUrlValidator < ActiveModel::EachValidator
  BLOCKED_HOSTS = %w[localhost localhost.localdomain].freeze
  PRIVATE_IP_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("255.255.255.255/32"),
    IPAddr.new("::/128"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8"),
    IPAddr.new("2001:db8::/32")
  ].freeze

  def validate_each(record, attribute, value)
    uri = parse_uri(value)
    return record.errors.add(attribute, "must be a valid URL") unless uri

    host = uri.host.to_s.downcase

    if require_https? && uri.scheme != "https"
      record.errors.add(attribute, "must use HTTPS")
      return
    end

    return if host_allowed?(host)

    if blocked_host?(host)
      record.errors.add(attribute, "cannot target local or private addresses")
      return
    end

    addresses = resolve_addresses(host)
    if addresses.empty?
      record.errors.add(attribute, "must resolve to a public IP address")
      return
    end

    if addresses.any? { |address| private_address?(address) }
      record.errors.add(attribute, "cannot target local or private addresses")
    end
  end

  private

  def parse_uri(value)
    uri = URI.parse(value.to_s)
    return unless uri.is_a?(URI::HTTP)
    return if uri.host.blank?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def blocked_host?(host)
    BLOCKED_HOSTS.include?(host) || host.end_with?(".local")
  end

  def host_allowed?(host)
    allowed_hosts.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }
  end

  def allowed_hosts
    ENV.fetch("WEBHOOK_ALLOWED_HOSTS", "")
       .split(",")
       .map { |entry| entry.strip.downcase }
       .reject(&:blank?)
  end

  def resolve_addresses(host)
    parsed_ip = IPAddr.new(host)
    [ parsed_ip ]
  rescue IPAddr::InvalidAddressError
    Resolv.getaddresses(host).filter_map do |address|
      IPAddr.new(address)
    rescue IPAddr::InvalidAddressError
      nil
    end
  rescue Resolv::ResolvError
    []
  end

  def private_address?(address)
    return false if Rails.env.development?

    PRIVATE_IP_RANGES.any? { |range| range.include?(address) }
  end

  def require_https?
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch("WEBHOOK_REQUIRE_HTTPS", Rails.env.production?.to_s)
    )
  end
end
