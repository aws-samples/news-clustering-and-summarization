resource "time_sleep" "wait_30_seconds" {
  depends_on = [aws_sqs_queue.dead_letter_queue, aws_kinesis_stream.input_stream, aws_iam_role.cloudwatch_event_role, aws_iam_role_policy.eventbridge_sfn_policy, aws_sfn_state_machine.pre_processing_sfn]

  create_duration = "30s"
}

#SQS Queue
resource "aws_sqs_queue" "dead_letter_queue" {
  name                    = "dead-letter-pipe-${local.standard_resource_name}"
  sqs_managed_sse_enabled = true
}

# Eventbridge rule used to trigger step functions off kinesis 
resource "aws_pipes_pipe" "event_pipe" {
  depends_on = [time_sleep.wait_30_seconds, aws_sqs_queue.dead_letter_queue, aws_kinesis_stream.input_stream, aws_iam_role.cloudwatch_event_role, aws_iam_role_policy.eventbridge_sfn_policy, aws_sfn_state_machine.pre_processing_sfn]
  name       = "event-pipe-${local.standard_resource_name}"
  role_arn   = aws_iam_role.cloudwatch_event_role.arn
  source     = aws_kinesis_stream.input_stream.arn
  target     = aws_sfn_state_machine.pre_processing_sfn.arn

  source_parameters {
    kinesis_stream_parameters {
      batch_size             = 1
      parallelization_factor = 1
      starting_position      = "TRIM_HORIZON"
      maximum_retry_attempts = 0
      dead_letter_config {
        arn = aws_sqs_queue.dead_letter_queue.arn
      }
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}
