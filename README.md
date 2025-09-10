# S3 Batch Processing with Step Functions Distributed Map + ECS

A production-ready AWS SAM solution for processing large numbers of S3 objects in parallel using AWS Step Functions Distributed Map with ECS workers on EC2 instances.

## 🏗️ Architecture

```text
S3 Bucket (input/ folder)
    ↓
Step Functions Distributed Map (discovers objects)
    ↓ (distributes tasks)
Step Functions Activity (task queue)
    ↓ (workers poll for tasks)
ECS Worker Pool (Dynamic Auto Scaling EC2 instances)
    ↓ (processes objects)
S3 Bucket (processed/ folder) + CloudWatch Logs
```

## ✨ Key Features

- **🚀 Dynamic Scaling**: Worker count specified at execution time (1-100 workers)
- **⚡ Fast**: Parallel processing with distributed map pattern
- **💰 Cost-Effective**: Dynamic scaling, pay only when processing
- **🔄 Reliable**: Built-in retry logic and error handling
- **📊 Observable**: Comprehensive structured JSON logging
- **🐳 Containerized**: Uses Docker image from application code
- **🌐 Portable**: Dynamic VPC discovery, works across accounts/regions
- **🎯 Flexible**: Easy adaptation to any workload size

## 🚀 Quick Start

### 📋 Prerequisites

- **AWS SAM CLI** installed and configured
- **AWS CLI** configured with appropriate region
- **Docker** installed and running
- **AWS Permissions** for ECS, Step Functions, S3, ECR, CloudFormation, Auto Scaling
- **jq** for JSON processing

### 🔧 Deploy

This solution uses **AWS SAM (Serverless Application Model)** for infrastructure deployment and management.

```bash
# Deploy with default settings (ASG max size: 100)
./deploy.sh

# Or customize deployment with instance type
./deploy.sh 5 m5.large    # Still works, but worker count is now dynamic
```

The deployment script uses `sam build` and `sam deploy` commands to provision all AWS resources defined in the SAM template.

### 🧪 Test & Execute

```bash
# Run end-to-end test with default 3 workers
./test.sh

# Run test with custom worker count
./test.sh 10

# Execute with specific worker count
./execute.sh 5          # 5 workers
./execute.sh 20         # 20 workers
./execute.sh 50         # 50 workers

# Execute with custom S3 prefix
./execute.sh 10 data/   # 10 workers, process 'data/' prefix
```

**Script Differences:**
- **`test.sh`**: Complete end-to-end test - generates files, monitors execution, verifies results
- **`execute.sh`**: Quick execution launcher - uses existing S3 files, starts workflow and exits

### 🧹 Cleanup

```bash
# Remove all resources
./cleanup.sh
```

## 📁 Project Structure

```text
├── README.md                    # This guide
├── template.yaml               # AWS SAM template with dynamic scaling (max 100)
├── deploy.sh                   # SAM deployment script
├── test.sh                     # End-to-end test with dynamic worker count
├── execute.sh                  # Simple execution script for any worker count
├── cleanup.sh                  # Resource cleanup
├── build-and-push.sh          # Docker build/push script
├── application/                # Application code
│   ├── processor.py           # Worker with activity polling & structured logging
│   ├── requirements.txt       # Python dependencies
│   └── Dockerfile            # Container definition
├── functions/                  # Lambda functions
│   └── ecs_provisioner/      # Dynamic ECS provisioning logic
└── statemachine/              # Step Functions workflow
    └── workflow-complete.asl.json  # Accepts dynamic worker_count input
```

## ⚙️ Dynamic Worker Configuration

### 🎯 Execution Input Format

```json
{
  "objects": [
    {"Key": "input/file1.txt"},
    {"Key": "input/file2.txt"}
  ],
  "worker_count": 10
}
```

### 🖥️ Instance Types

- **t3.medium** - Cost-effective, light workloads
- **c5.large** - CPU-intensive processing (default)
- **m5.large** - Balanced CPU/memory
- **m5.xlarge** - Memory-intensive workloads

### 📊 Expected Performance

| Workers | Instance Type | Objects | Processing Time | Throughput |
|---------|---------------|---------|----------------|------------|
| 3       | c5.large     | 50      | ~4 minutes     | 750 obj/hr |
| 5       | c5.large     | 50      | ~2.5 minutes   | 1200 obj/hr |
| 10      | c5.large     | 50      | ~1.5 minutes   | 2000 obj/hr |
| 20      | m5.large     | 100     | ~1.5 minutes   | 4000 obj/hr |

## 🔍 Monitoring

### 📋 CloudWatch Logs

```bash
# View worker logs
aws logs describe-log-streams \
  --log-group-name "/ecs/s3-batch-processor-s3-batch-processor" \
  --region ap-east-1
```

### 📊 Key Log Messages

- `"Processing task"` - Task received from Step Functions Activity
- `"Processing S3 object"` - Object processing started
- `"S3 object processed successfully"` - Processing completed
- `"Task completed"` - Task finished with count

### 🎯 Step Functions Console

- Visual workflow execution tracking
- Distributed map performance metrics
- Error details and retry information

## 🎨 Customizing Processing Logic

The core processing happens in `application/processor.py`. Modify the `process_s3_object()` method:

```python
def process_s3_object(self, object_key: str, bucket: str = None) -> Dict[str, Any]:
    # Your custom processing logic here
    # - Image processing: resize, filter, analyze
    # - Data transformation: parse, validate, enrich
    # - ML inference: classify, predict, score
    # - File conversion: PDF to text, format conversion
    
    # Current implementation: 5-second processing simulation
    time.sleep(5)
    
    # Return structured result
    return {
        'object_key': object_key,
        'processed_key': processed_key,
        'content': content,
        'processing_time': processing_time,
        'processed_at': datetime.utcnow().isoformat(),
        'worker_id': self.worker_id,
        'status': 'success'
    }
```

## 🔒 Security Features

- ✅ **IAM Roles**: Least privilege access managed by SAM
- ✅ **Dynamic VPC**: Uses default VPC, no hardcoded values
- ✅ **Container Security**: Non-root user execution
- ✅ **S3 Access**: Scoped to specific bucket/prefixes
- ✅ **SAM Security**: Infrastructure as Code with version control

## 🎯 Production Considerations

### 💰 Cost Optimization

- **Zero cost when idle**: ASG scales to 0 when no processing
- **Dynamic worker count**: Scale exactly to your workload needs
- **Efficient processing**: 5-second processing time per object
- **Automatic cleanup**: Infrastructure scales down after completion

### 📈 Scaling Guidelines

- **Small workloads (< 50 objects)**: 2-5 workers
- **Medium workloads (50-500 objects)**: 5-20 workers
- **Large workloads (500+ objects)**: 20-100 workers
- **Maximum capacity**: 100 workers (configurable in template.yaml)

### 🔧 Tested Configuration

- **✅ Dynamic worker count**: 1-100 workers tested and working
- **✅ 1:1:1 ratio**: 1 worker = 1 EC2 instance = 1 ECS task
- **✅ Dynamic VPC discovery**: Portable across accounts
- **✅ Proper logging**: Structured JSON logs with processing details
- **✅ Complete lifecycle**: Provision → Process → Deprovision
- **✅ AWS SAM deployment**: Infrastructure as Code with repeatable deployments

## 🛠️ SAM Commands

```bash
# Build the application
sam build

# Deploy with guided prompts
sam deploy --guided

# Deploy with custom max workers (default: 100)
sam deploy --parameter-overrides MaxWorkers=200

# View stack outputs
sam list stack-outputs

# Delete the stack
sam delete
```

## 🚀 Usage Examples

```bash
# Process 10 files with 3 workers
./execute.sh 3

# Process 100 files with 25 workers for faster throughput
./execute.sh 25

# Process files from 'data/' prefix with 10 workers
./execute.sh 10 data/

# Run comprehensive test with 5 workers
./test.sh 5

# Multiple concurrent executions for load testing
./execute.sh 5 && ./execute.sh 8 && ./execute.sh 12
```

---

**🎉 Ready to process thousands of S3 objects efficiently with dynamic AWS SAM scaling!**
