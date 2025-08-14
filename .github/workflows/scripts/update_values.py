import sys
from ruamel.yaml import YAML


def update_image_tag(file_path, new_tag):
    """
    # Updates the image tag in a YAML file while preserving comments and structure.

    Args:
        file_path (str): The path to the values.yaml file.
        new_tag (str): The new Docker image tag to set.
    """
    yaml = YAML()
    yaml.preserve_quotes = True

    try:
        with open(file_path) as f:
            data = yaml.load(f)

        data["backend"]["image"]["tag"] = new_tag

        with open(file_path, "w") as f:
            yaml.dump(data, f)

        print(f"✅ Successfully updated {file_path} with image tag: {new_tag}")

    except FileNotFoundError:
        print(f"❌ Error: The file {file_path} was not found.")
        sys.exit(1)
    except KeyError:
        print(f"❌ Error: Could not find 'image.tag' path in {file_path}.")
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python update_values.py <path_to_values_yaml> <new_tag>")
        sys.exit(1)

    values_file = sys.argv[1]
    image_tag = sys.argv[2]
    update_image_tag(values_file, image_tag)
