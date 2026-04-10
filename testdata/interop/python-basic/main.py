from util import helper


def main(value: int) -> int:
    return helper(value + 1)


if __name__ == "__main__":
    result = main(3)
    print(result)
