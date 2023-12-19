from sagemaker.s3 import S3Uploader
import sagemaker
import boto3
import argparse
import yaml

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-output-bucket",
        "--output-bucket",
        dest="output_bucket",
        help="The S3 bucket name output data for training",
    )
    parser.add_argument(
        "-role",
        "--role",
        dest="role",
        help="The role ARN",
    )
    parser.add_argument(
        "-pipeline",
        "--pipeline",
        dest="pipeline",
        help="The pipeline type folder",
    )
    args = parser.parse_args()
    # Upload the data from the local dataset folder to the default bucket
    # output_bucket = sagemaker.Session().default_bucket()
    output_bucket = args.output_bucket

    local_data_file = "./datasets/template.json"
    data_s3_location = f"s3://{output_bucket}/llm-evaluation-at-scale-example"
    training_s3_location = f"{data_s3_location}/train_dataset"
    validation_s3_location = f"{data_s3_location}/val_dataset"

    print(f"Default data location: {data_s3_location}")
    print(f"Default train location: {training_s3_location}")
    print(f"Default data location: {validation_s3_location}")

    S3Uploader.upload("./datasets/evaluation_dataset_trivia.jsonl", data_s3_location)
    S3Uploader.upload("./datasets/train_dataset_trivia.jsonl", training_s3_location)
    S3Uploader.upload("./datasets/template.json", training_s3_location)
    S3Uploader.upload(
        "./datasets/validation_dataset_trivia.jsonl", validation_s3_location
    )
    S3Uploader.upload("./datasets/template.json", validation_s3_location)
    fname = f"./{args.pipeline}/config.yaml"
    stream = open(fname, "r")
    data = yaml.load(stream, Loader=yaml.Loader)
    data["SageMaker"]["PythonSDK"]["Modules"]["RemoteFunction"]["RoleArn"] = args.role
    with open(fname, "w") as yaml_file:
        yaml_file.write(yaml.dump(data, default_flow_style=False))
