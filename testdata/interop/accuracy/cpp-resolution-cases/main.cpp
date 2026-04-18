#include <string>

namespace service {
class Handler {
  public:
    std::string run() const { return "ok"; }
};
}  // namespace service

int main() {
  service::Handler handler;
  return handler.run().size();
}
