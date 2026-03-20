# Installation and Dependencies

The project requires:

- Python 3.10+

- Python packages:

  - synthcity

  - torch (CPU-only or GPU version)

  - ipykernel (for Jupyter notebooks)

  - boto3 and awscli (for AWS S3 access)

  - Other optional utilities: numpy, pandas, scikit-learn

# Using a Docker Container (recommended)

The provided Docker setup includes Python 3.10, SynthCity, and CPU-only PyTorch.

Build the Docker image:

# Make a copy of your Dockerfile (optional)
cp Dockerfile Dockerfile-Python3.10

# Edit Dockerfile-Python3.10 to include SynthCity (see provided snippet)
nano Dockerfile-Python3.10

# Build the image
docker build -f Dockerfile-Python3.10 -t megkern-rstudio:synthcity .

# Run the container
docker run -p 8787:8787 -p 8888:8888 megkern-rstudio:synthcity

Notes:

Virtual environment is located at /opt/synthcity-env.

Jupyter notebooks automatically show the Python 3.10 (synthcity) kernel.

S3 access works via environment variables, shared config files, or EC2 IAM roles.

Using Desktop Python

If running locally without Docker:

# Create a virtual environment
python3.10 -m venv synthcity-env
source synthcity-env/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install torch==2.2.2+cpu synthcity ipykernel boto3 awscli

Optional: Register a Jupyter kernel:

python -m ipykernel install --name synthcity --display-name "Python 3.10 (synthcity)"
AWS S3 Access

Ensure AWS credentials are available via:

Environment variables (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)

~/.aws/credentials file

EC2 IAM roles

Both Docker and desktop Python environments can access S3 seamlessly.

Getting Started

Minimal example to confirm SynthCity is working:

import synthcity
import pandas as pd
from synthcity.plugins.core.models import GaussianCopula
import sys

print("Python version:", sys.version)

# Sample dataset
data = pd.DataFrame({
    "age": [25, 32, 47, 51],
    "income": [50000, 60000, 80000, 90000],
    "purchased": [0, 1, 1, 0]
})

# Initialize SynthCity model
model = GaussianCopula()
model.fit(data)

# Generate synthetic samples
synthetic_data = model.sample(5)
print("Synthetic samples:")
print(synthetic_data)

Notes:

Docker users: Launch the container with the Python 3.10 (synthcity) kernel or activate /opt/synthcity-env.

Desktop Python users: Activate the virtual environment before running the script:

source synthcity-env/bin/activate

S3 integration: Works automatically if AWS credentials are configured.
