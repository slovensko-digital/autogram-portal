class DocumentPolicy < ApplicationPolicy
  def visualize?
    context.is_a?(AuthorizationContext::Web)
  end

  def pdf_preview?
    visualize?
  end

  def download?
    visualize?
  end
end
