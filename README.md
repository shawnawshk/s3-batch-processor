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
ECS Worker Pool (Auto Scaling EC2 instances)
    ↓ (processes objects)
S3 Bucket (processed/ folder) + CloudWatch Logs
```

## ✨ Key Features

- **🚀 Scalable**: Configurable EC2 workers with Auto Scaling (0 → N → 0)
- **⚡ Fast**: Parallel processing with distributed map pattern
- **💰 Cost-Effective**: Dynamic scaling, pay only when processing
- **🔄 Reliable**: Built-in retry logic and error handling
- **📊 Observable**: Comprehensive structured JSON logging
- **🐳 Containerized**: Uses Docker image from application code
- **🌐 Portable**: Dynamic VPC discovery, works across accounts/regions

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
# Deploy with default settings (3 c5.large instances)
./deploy.sh

# Or customize deployment
./deploy.sh 5 m5.large    # 5 m5.large instances
./deploy.sh 10 c5.xlarge  # 10 c5.xlarge instances
```

The deployment script uses `sam build` and `sam deploy` commands to provision all AWS resources defined in the SAM template.

### 🧪 Test

```bash
# Run end-to-end test
./test.sh
```

### 🧹 Cleanup

```bash
# Remove all resources
./cleanup.sh
```

## 📁 Project Structure

```text
├── README.md                    # This guide
├── template.yaml               # AWS SAM template with dynamic VPC discovery
├── deploy.sh                   # SAM deployment script
├── test.sh                     # End-to-end test
├── cleanup.sh                  # Resource cleanup
├── build-and-push.sh          # Docker build/push script
├── application/                # Application code
│   ├── processor.py           # Worker with activity polling & structured logging
│   ├── requirements.txt       # Python dependencies
│   └── Dockerfile            # Container definition
├── functions/                  # Lambda functions
│   └── ecs_provisioner/      # ECS provisioning logic
└── statemachine/              # Step Functions workflow
    └── workflow-complete.asl.json
```

## ⚙️ Configuration

### 🖥️ Instance Types

- **t3.medium** - Cost-effective, light workloads
- **c5.large** - CPU-intensive processing (default)
- **m5.large** - Balanced CPU/memory
- **m5.xlarge** - Memory-intensive workloads

### 📊 Expected Performance

| Workers | Instance Type | Objects | Processing Time | Throughput |
|---------|---------------|---------|----------------|------------|
| 3       | c5.large     | 5       | ~1.5 minutes   | 200 obj/hr |
| 5       | c5.large     | 10      | ~1.5 minutes   | 400 obj/hr |
| 10      | m5.large     | 20      | ~2 minutes     | 600 obj/hr |

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
- **Right-sized instances**: Choose appropriate instance types
- **Efficient processing**: 5-second processing time per object
- **Automatic cleanup**: Infrastructure scales down after completion

### 📈 Scaling Guidelines

- **Small workloads (< 50 objects)**: 2-3 workers
- **Medium workloads (50-500 objects)**: 5-10 workers  
- **Large workloads (500+ objects)**: 10+ workers

### 🔧 Tested Configuration

- **✅ 3 c5.large EC2 instances**: Proven to work reliably
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

# Deploy with parameters
sam deploy --parameter-overrides ParameterKey=WorkerCount,ParameterValue=5

# View stack outputs
sam list stack-outputs

# Delete the stack
sam delete
```

---

**🎉 Ready to process thousands of S3 objects efficiently with AWS SAM and dynamic EC2 scaling!**
