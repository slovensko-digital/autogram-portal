require "test_helper"

class GoodJobAccessTest < ActionDispatch::IntegrationTest
  test "good_job dashboard requires authentication" do
    get "/admin/good_job"

    assert_response :redirect
    assert_includes response.headers["Location"], "/users/sign_in"
  end
end
