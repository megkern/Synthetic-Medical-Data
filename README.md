# Installation and Dependencies

The project requires:

- Python 3.10+

- Python packages:

  - synthcity

  - torch (CPU-only or GPU version)

  - ipykernel (for Jupyter notebooks)

  - boto3 and awscli (for AWS S3 access)

  - Other optional utilities: numpy, pandas, scikit-learn

# Running the Python Script with SynthCity

This project uses **SynthCity** for generating synthetic data. You can run it in a Docker container or on a local python environment.

---

## Using the Docker Container

We provide a template Dockerfile (`Dockerfile-Python3.10`) that installs:

- Python 3.10
- A dedicated virtual environment at `/opt/synthcity-env`
- CPU-only PyTorch
- SynthCity and Jupyter kernel registration

### Steps to use:

1. Copy the template Dockerfile to your project folder:

```bash
cp path/to/Dockerfile-Python3.10 .
```

2. Edit placeholders if needed (for startup scripts, additional dependencies, or AWS credentials).

3. Build the image:

```bash
docker build -f Dockerfile-Python3.10 -t my-synthcity-image .
```

4. Run the container:

```bash
docker run -p 8787:8787 -p 8888:8888 my-synthcity-image
```

5. Inside Jupyter, select the Python 3.10 (synthcity) kernel.


## Using Desktop Python (Optional)

If you prefer to run locally:

- Create a Python 3.10 virtual environment.

- Install the required packages: synthcity, torch, ipykernel, boto3, awscli.

- Activate the virtual environment and select it in Jupyter if needed.

## Getting Started

Minimal example to confirm SynthCity is working:

```python
import synthcity
import pandas as pd
from synthcity.plugins.core.models import GaussianCopula
import sys

print("Python version:", sys.version)

data = pd.DataFrame({
    "age": [25, 32, 47, 51],
    "income": [50000, 60000, 80000, 90000],
    "purchased": [0, 1, 1, 0]
})

model = GaussianCopula()
model.fit(data)

synthetic_data = model.sample(5)
print("Synthetic samples:")
print(synthetic_data)
```
