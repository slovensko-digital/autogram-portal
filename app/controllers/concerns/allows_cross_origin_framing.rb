# Lets integrators embed the response in an iframe on any HTTPS origin, on top of
# the frame ancestors allowed in config/initializers/content_security_policy.rb.
module AllowsCrossOriginFraming
  private

  def allow_cross_origin_framing
    response.headers.except! "X-Frame-Options"
    request.content_security_policy = current_content_security_policy.tap do |policy|
      policy.frame_ancestors(*policy.directives["frame-ancestors"], :https)
    end
  end
end
