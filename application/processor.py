#!/usr/bin/env python3
"""
Activity-based Worker for S3 Batch Processing PoC
Persistent worker that polls Step Functions Activity for tasks
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from typing import Dict, Any, Optional

import boto3
from botocore.exceptions import ClientError, BotoCoreError
from pythonjsonlogger import jsonlogger

# Configure structured logging
def setup_logging():
    """Setup structured JSON logging"""
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # Remove default handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # Add JSON formatter
    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        '%(asctime)s %(name)s %(levelname)s %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger

logger = setup_logging()

class ActivityWorker:
    """Persistent worker that processes tasks from Step Functions Activity"""
    
    def __init__(self):
        self.stepfunctions_client = boto3.client('stepfunctions', region_name='ap-east-1')
        self.s3_client = boto3.client('s3', region_name='ap-east-1')
        
        # Get configuration from environment
        self.activity_arn = os.environ.get('ACTIVITY_ARN')
        self.bucket = os.environ.get('S3_BUCKET')
        self.worker_id = os.environ.get('WORKER_ID', 'unknown-worker')
        
        # Validate required environment variables
        if not self.activity_arn:
            raise ValueError("ACTIVITY_ARN environment variable is required")
        if not self.bucket:
            raise ValueError("S3_BUCKET environment variable is required")
        
        self.processed_count = 0
        self.running = True
        
        logger.info("Activity worker initialized", extra={
            'worker_id': self.worker_id,
            'activity_arn': self.activity_arn,
            'bucket': self.bucket
        })
    
    def get_activity_task(self) -> Optional[Dict[str, Any]]:
        """Poll for a task from Step Functions Activity"""
        try:
            logger.info("Polling for activity task", extra={
                'worker_id': self.worker_id,
                'activity_arn': self.activity_arn
            })
            
            response = self.stepfunctions_client.get_activity_task(
                activityArn=self.activity_arn,
                workerName=self.worker_id
            )
            
            logger.info("Received response from get_activity_task", extra={
                'worker_id': self.worker_id,
                'has_task_token': 'taskToken' in response and bool(response.get('taskToken'))
            })
            
            if 'taskToken' in response and response['taskToken']:
                task_input = json.loads(response['input'])
                logger.info("Got activity task", extra={
                    'worker_id': self.worker_id,
                    'task_input': task_input
                })
                return {
                    'task_token': response['taskToken'],
                    'input': task_input
                }
            
            logger.info("No task available", extra={
                'worker_id': self.worker_id
            })
            return None
            
        except Exception as e:
            logger.error("Failed to get activity task", extra={
                'worker_id': self.worker_id,
                'error': str(e),
                'error_type': type(e).__name__
            })
            return None
    
    def process_s3_object(self, object_key: str) -> Dict[str, Any]:
        """Process a single S3 object - one at a time"""
        start_time = time.time()
        
        logger.info("Processing S3 object", extra={
            'worker_id': self.worker_id,
            'object_key': object_key,
            'bucket': self.bucket,
            'processing_mode': 'single_task'
        })
        
        try:
            # Get object content
            response = self.s3_client.get_object(
                Bucket=self.bucket,
                Key=object_key
            )
            
            content = response['Body'].read().decode('utf-8').strip()
            
            # Simulate processing time (5 seconds as per requirement)
            time.sleep(5)
            
            processing_time = time.time() - start_time
            
            result = {
                'object_key': object_key,
                'content': content,
                'processing_time': round(processing_time, 2),
                'processed_at': datetime.utcnow().isoformat(),
                'worker_id': self.worker_id,
                'status': 'success'
            }
            
            logger.info("S3 object processed successfully", extra={
                'worker_id': self.worker_id,
                'object_key': object_key,
                'processing_time': processing_time
            })
            return result
            
        except Exception as e:
            processing_time = time.time() - start_time
            
            result = {
                'object_key': object_key,
                'error': str(e),
                'processing_time': round(processing_time, 2),
                'processed_at': datetime.utcnow().isoformat(),
                'worker_id': self.worker_id,
                'status': 'error'
            }
            
            logger.error("Failed to process S3 object", extra=result)
            return result
    
    def send_task_success(self, task_token: str, result: Dict[str, Any]):
        """Send task success back to Step Functions"""
        try:
            self.stepfunctions_client.send_task_success(
                taskToken=task_token,
                output=json.dumps(result)
            )
            
            logger.info("Sent task success", extra={
                'worker_id': self.worker_id,
                'result': result
            })
            
        except Exception as e:
            logger.error("Failed to send task success", extra={
                'worker_id': self.worker_id,
                'error': str(e)
            })
    
    def send_task_failure(self, task_token: str, error: str):
        """Send task failure back to Step Functions"""
        try:
            self.stepfunctions_client.send_task_failure(
                taskToken=task_token,
                error='ProcessingError',
                cause=error
            )
            
            logger.error("Sent task failure", extra={
                'worker_id': self.worker_id,
                'error': error
            })
            
        except Exception as e:
            logger.error("Failed to send task failure", extra={
                'worker_id': self.worker_id,
                'error': str(e)
            })
    
    def run(self):
        """Main worker loop - continuously poll for tasks"""
        logger.info("Starting activity worker", extra={
            'worker_id': self.worker_id
        })
        
        poll_count = 0
        
        while self.running:
            try:
                poll_count += 1
                logger.info("Worker loop iteration", extra={
                    'worker_id': self.worker_id,
                    'poll_count': poll_count
                })
                
                # Poll for a task
                task = self.get_activity_task()
                
                if task:
                    task_token = task['task_token']
                    task_input = task['input']
                    object_key = task_input.get('object_key')
                    
                    if object_key:
                        # Process the object
                        result = self.process_s3_object(object_key)
                        
                        # Send result back to Step Functions
                        if result['status'] == 'success':
                            self.send_task_success(task_token, result)
                        else:
                            self.send_task_failure(task_token, result.get('error', 'Unknown error'))
                        
                        self.processed_count += 1
                        
                        logger.info("Task completed", extra={
                            'worker_id': self.worker_id,
                            'processed_count': self.processed_count,
                            'object_key': object_key
                        })
                        
                        # Immediately poll for next task (no delay between tasks)
                        continue
                    else:
                        self.send_task_failure(task_token, "No object_key in task input")
                
                else:
                    # No task available, wait a bit before polling again
                    logger.info("No task available, waiting before next poll", extra={
                        'worker_id': self.worker_id,
                        'poll_count': poll_count
                    })
                    time.sleep(1)
                    
            except KeyboardInterrupt:
                logger.info("Received shutdown signal", extra={
                    'worker_id': self.worker_id,
                    'processed_count': self.processed_count
                })
                self.running = False
                
            except Exception as e:
                logger.error("Unexpected error in worker loop", extra={
                    'worker_id': self.worker_id,
                    'error': str(e),
                    'error_type': type(e).__name__,
                    'poll_count': poll_count
                })
                time.sleep(5)  # Wait before retrying
        
        logger.info("Activity worker stopped", extra={
            'worker_id': self.worker_id,
            'total_processed': self.processed_count
        })

def main():
    """Main entry point"""
    try:
        worker = ActivityWorker()
        worker.run()
        
    except Exception as e:
        logger.error("Fatal error in worker", extra={
            'error': str(e)
        })
        sys.exit(1)

if __name__ == '__main__':
    main()