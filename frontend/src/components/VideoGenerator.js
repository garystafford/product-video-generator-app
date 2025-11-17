import React, { useState, useEffect } from 'react';
import {
  Container,
  SpaceBetween,
  FormField,
  Input,
  Textarea,
  Select,
  Button,
  Alert,
  ColumnLayout,
  Box,
  FileUpload,
  Cards,
  Header,
  ProgressBar,
  StatusIndicator
} from '@cloudscape-design/components';
import axios from 'axios';

function VideoGenerator() {
  const [productName, setProductName] = useState('');
  const [prompt, setPrompt] = useState('');
  const [s3Bucket, setS3Bucket] = useState('');
  const [startFrame, setStartFrame] = useState([]);
  const [endFrame, setEndFrame] = useState([]);
  const [startFramePreview, setStartFramePreview] = useState(null);
  const [endFramePreview, setEndFramePreview] = useState(null);

  // Video settings
  const [aspectRatio, setAspectRatio] = useState({ label: '16:9', value: '16:9' });
  const [duration, setDuration] = useState({ label: '5 seconds', value: '5s' });
  const [resolution, setResolution] = useState({ label: '720p', value: '720p' });
  const [loop, setLoop] = useState({ label: 'No', value: 'false' });

  // Config options from API
  const [configOptions, setConfigOptions] = useState(null);

  // Available keyframes
  const [availableKeyframes, setAvailableKeyframes] = useState([]);

  // Status
  const [isUploading, setIsUploading] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const [alertMessage, setAlertMessage] = useState(null);
  const [currentJobId, setCurrentJobId] = useState(null);
  const [jobStatus, setJobStatus] = useState(null);

  const fetchAvailableKeyframes = async () => {
    try {
      const response = await axios.get('/api/keyframes/list');
      setAvailableKeyframes(response.data.products || []);
    } catch (err) {
      console.error('Failed to load keyframes:', err);
    }
  };

  useEffect(() => {
    // Load config options
    axios.get('/api/config/options')
      .then(response => setConfigOptions(response.data))
      .catch(err => console.error('Failed to load config options:', err));

    // Load environment config and set default S3 bucket
    axios.get('/api/config/environment')
      .then(response => {
        console.log('Environment config response:', response.data);
        if (response.data.s3_bucket_name) {
          console.log('Setting S3 bucket to:', response.data.s3_bucket_name);
          setS3Bucket(response.data.s3_bucket_name);
        } else {
          console.log('No S3 bucket name found in environment config');
        }
      })
      .catch(err => console.error('Failed to load environment config:', err));

    // Load available keyframes
    fetchAvailableKeyframes();
  }, []);

  useEffect(() => {
    // Poll job status if we have an active job
    if (currentJobId) {
      const interval = setInterval(() => {
        axios.get(`/api/jobs/${currentJobId}`)
          .then(response => {
            setJobStatus(response.data);
            if (response.data.status === 'completed' || response.data.status === 'failed') {
              clearInterval(interval);
              setIsGenerating(false);
              if (response.data.status === 'completed') {
                setAlertMessage({
                  type: 'success',
                  content: 'Video generated successfully! Check the Video Gallery to view it.'
                });
              } else {
                setAlertMessage({
                  type: 'error',
                  content: `Video generation failed: ${response.data.error || 'Unknown error'}`
                });
              }
            }
          })
          .catch(err => {
            console.error('Failed to fetch job status:', err);
            clearInterval(interval);
          });
      }, 2000);

      return () => clearInterval(interval);
    }
  }, [currentJobId]);

  const handleStartFrameChange = ({ detail }) => {
    setStartFrame(detail.value);
    if (detail.value.length > 0) {
      const reader = new FileReader();
      reader.onload = (e) => setStartFramePreview(e.target.result);
      reader.readAsDataURL(detail.value[0]);
    } else {
      setStartFramePreview(null);
    }
  };

  const handleEndFrameChange = ({ detail }) => {
    setEndFrame(detail.value);
    if (detail.value.length > 0) {
      const reader = new FileReader();
      reader.onload = (e) => setEndFramePreview(e.target.result);
      reader.readAsDataURL(detail.value[0]);
    } else {
      setEndFramePreview(null);
    }
  };

  const handleUploadKeyframes = async () => {
    if (!productName || startFrame.length === 0) {
      setAlertMessage({
        type: 'error',
        content: 'Please provide product name and start frame'
      });
      return;
    }

    setIsUploading(true);
    setAlertMessage(null);

    try {
      const formData = new FormData();
      formData.append('product_name', productName);
      formData.append('start_frame', startFrame[0]);
      if (endFrame.length > 0) {
        formData.append('end_frame', endFrame[0]);
      }

      const response = await axios.post('/api/keyframes/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });

      setAlertMessage({
        type: 'success',
        content: 'Keyframes uploaded successfully!'
      });

      // Refresh the available keyframes list
      await fetchAvailableKeyframes();
    } catch (error) {
      setAlertMessage({
        type: 'error',
        content: `Upload failed: ${error.response?.data?.detail || error.message}`
      });
    } finally {
      setIsUploading(false);
    }
  };

  const handleGenerateVideo = async () => {
    if (!productName || !prompt || !s3Bucket) {
      setAlertMessage({
        type: 'error',
        content: 'Please fill in all required fields'
      });
      return;
    }

    setIsGenerating(true);
    setAlertMessage(null);
    setJobStatus(null);

    try {
      const requestData = {
        product_name: productName,
        prompt: prompt,
        s3_bucket: s3Bucket,
        settings: {
          aspect_ratio: aspectRatio.value,
          duration: duration.value,
          resolution: resolution.value,
          loop: loop.value === 'true',
          region: 'us-west-2'
        }
      };

      const response = await axios.post('/api/videos/generate', requestData);

      setCurrentJobId(response.data.job_id);
      setAlertMessage({
        type: 'info',
        content: 'Video generation started! This may take 3-6 minutes.'
      });
    } catch (error) {
      setIsGenerating(false);
      setAlertMessage({
        type: 'error',
        content: `Generation failed: ${error.response?.data?.detail || error.message}`
      });
    }
  };

  const aspectRatioOptions = configOptions?.aspect_ratios.map(ar => ({
    label: ar,
    value: ar
  })) || [];

  const durationOptions = [
    { label: '5 seconds', value: '5s' },
    { label: '10 seconds', value: '10s' }
  ];

  const resolutionOptions = [
    { label: '720p', value: '720p' },
    { label: '540p', value: '540p' }
  ];

  const loopOptions = [
    { label: 'Yes', value: 'true' },
    { label: 'No', value: 'false' }
  ];

  return (
    <SpaceBetween size="l">
      {alertMessage && (
        <Alert
          type={alertMessage.type}
          dismissible
          onDismiss={() => setAlertMessage(null)}
        >
          {alertMessage.content}
        </Alert>
      )}

      <Container header={<Header variant="h2">Product Information</Header>}>
        <SpaceBetween size="l">
          <FormField
            label="Product Name"
            description="Unique identifier for your product video"
          >
            <Input
              value={productName}
              onChange={({ detail }) => setProductName(detail.value)}
              placeholder="e.g., watch, sneaker, bottle"
              disabled={isGenerating}
            />
          </FormField>

          <FormField
            label="S3 Bucket"
            description="AWS S3 bucket where generated video will be stored (defaults to S3_BUCKET_NAME environment variable)"
          >
            <Input
              value={s3Bucket}
              onChange={({ detail }) => setS3Bucket(detail.value)}
              placeholder="e.g., my-video-bucket"
              disabled={isGenerating}
            />
          </FormField>
        </SpaceBetween>
      </Container>

      <Container header={
        <Header
          variant="h2"
          description={`${availableKeyframes.length} product${availableKeyframes.length !== 1 ? 's' : ''} with keyframes`}
        >
          Available Keyframes
        </Header>
      }>
        {availableKeyframes.length === 0 ? (
          <Box textAlign="center" color="text-body-secondary" padding={{ vertical: 'l' }}>
            No keyframes uploaded yet. Upload your first keyframes below.
          </Box>
        ) : (
          <Cards
            cardDefinition={{
              header: item => (
                <Box variant="h3">{item.product_name}</Box>
              ),
              sections: [
                {
                  id: 'preview',
                  content: item => (
                    <ColumnLayout columns={2} borders="vertical">
                      <Box textAlign="center">
                        <Box variant="awsui-key-label" margin={{ bottom: 'xs' }}>
                          Start Frame
                        </Box>
                        {item.start_frame ? (
                          <img
                            src={`/api/keyframes/${item.product_name}/start`}
                            alt={`${item.product_name} start frame`}
                            style={{
                              width: '100%',
                              maxHeight: '150px',
                              objectFit: 'contain',
                              borderRadius: '4px',
                              border: '1px solid #e9ebed'
                            }}
                            onError={(e) => {
                              e.target.style.display = 'none';
                              e.target.nextSibling.style.display = 'block';
                            }}
                          />
                        ) : (
                          <Box
                            color="text-body-secondary"
                            padding={{ vertical: 'xxl' }}
                            textAlign="center"
                            fontSize="body-s"
                          >
                            No start frame
                          </Box>
                        )}
                      </Box>
                      <Box textAlign="center">
                        <Box variant="awsui-key-label" margin={{ bottom: 'xs' }}>
                          End Frame
                        </Box>
                        {item.end_frame ? (
                          <img
                            src={`/api/keyframes/${item.product_name}/end`}
                            alt={`${item.product_name} end frame`}
                            style={{
                              width: '100%',
                              maxHeight: '150px',
                              objectFit: 'contain',
                              borderRadius: '4px',
                              border: '1px solid #e9ebed'
                            }}
                            onError={(e) => {
                              e.target.style.display = 'none';
                              e.target.nextSibling.style.display = 'block';
                            }}
                          />
                        ) : (
                          <Box
                            color="text-body-secondary"
                            padding={{ vertical: 'xxl' }}
                            textAlign="center"
                            fontSize="body-s"
                          >
                            No end frame
                          </Box>
                        )}
                      </Box>
                    </ColumnLayout>
                  )
                },
                {
                  id: 'frames',
                  content: item => (
                    <SpaceBetween size="s">
                      <Box>
                        <StatusIndicator type={item.start_frame ? 'success' : 'error'}>
                          Start Frame: {item.start_frame ? '✓' : '✗'}
                        </StatusIndicator>
                      </Box>
                      <Box>
                        <StatusIndicator type={item.end_frame ? 'success' : 'warning'}>
                          End Frame: {item.end_frame ? '✓' : 'Not uploaded'}
                        </StatusIndicator>
                      </Box>
                    </SpaceBetween>
                  )
                }
              ]
            }}
            cardsPerRow={[
              { cards: 1 },
              { minWidth: 500, cards: 2 },
              { minWidth: 800, cards: 3 }
            ]}
            items={availableKeyframes}
            empty={
              <Box textAlign="center" color="text-body-secondary">
                No keyframes available
              </Box>
            }
          />
        )}
      </Container>

      <Container header={<Header variant="h2">Keyframe Images</Header>}>
        <SpaceBetween size="l">
          <ColumnLayout columns={2}>
            <FormField
              label="Start Frame"
              description="First frame of the video"
            >
              <SpaceBetween size="m">
                <FileUpload
                  value={startFrame}
                  onChange={handleStartFrameChange}
                  accept="image/jpeg,image/png,image/webp"
                  showFileSize
                  showFileLastModified
                  i18nStrings={{
                    uploadButtonText: e => e ? 'Choose file' : 'Choose file',
                    dropzoneText: e => e ? 'Drop file to upload' : 'Drop file to upload',
                    removeFileAriaLabel: e => `Remove file ${e + 1}`,
                    limitShowFewer: 'Show fewer files',
                    limitShowMore: 'Show more files',
                    errorIconAriaLabel: 'Error'
                  }}
                  disabled={isGenerating}
                />
                {startFramePreview && (
                  <Box textAlign="center">
                    <img
                      src={startFramePreview}
                      alt="Start frame preview"
                      style={{ maxWidth: '100%', maxHeight: '300px', borderRadius: '8px' }}
                    />
                  </Box>
                )}
              </SpaceBetween>
            </FormField>

            <FormField
              label="End Frame (Optional)"
              description="Last frame of the video"
            >
              <SpaceBetween size="m">
                <FileUpload
                  value={endFrame}
                  onChange={handleEndFrameChange}
                  accept="image/jpeg,image/png,image/webp"
                  showFileSize
                  showFileLastModified
                  i18nStrings={{
                    uploadButtonText: e => e ? 'Choose file' : 'Choose file',
                    dropzoneText: e => e ? 'Drop file to upload' : 'Drop file to upload',
                    removeFileAriaLabel: e => `Remove file ${e + 1}`,
                    limitShowFewer: 'Show fewer files',
                    limitShowMore: 'Show more files',
                    errorIconAriaLabel: 'Error'
                  }}
                  disabled={isGenerating}
                />
                {endFramePreview && (
                  <Box textAlign="center">
                    <img
                      src={endFramePreview}
                      alt="End frame preview"
                      style={{ maxWidth: '100%', maxHeight: '300px', borderRadius: '8px' }}
                    />
                  </Box>
                )}
              </SpaceBetween>
            </FormField>
          </ColumnLayout>

          <Box textAlign="right">
            <Button
              variant="primary"
              onClick={handleUploadKeyframes}
              loading={isUploading}
              disabled={isGenerating}
            >
              Upload Keyframes
            </Button>
          </Box>
        </SpaceBetween>
      </Container>

      <Container header={<Header variant="h2">Video Settings</Header>}>
        <SpaceBetween size="l">
          <FormField
            label="Animation Prompt"
            description="Describe the motion and animation you want in the video"
          >
            <Textarea
              value={prompt}
              onChange={({ detail }) => setPrompt(detail.value)}
              placeholder="e.g., A luxury wristwatch rotates clockwise on a reflective surface, with dramatic lighting highlighting its metallic details..."
              rows={4}
              disabled={isGenerating}
            />
          </FormField>

          <ColumnLayout columns={2}>
            <FormField label="Aspect Ratio">
              <Select
                selectedOption={aspectRatio}
                onChange={({ detail }) => setAspectRatio(detail.selectedOption)}
                options={aspectRatioOptions}
                disabled={isGenerating}
              />
            </FormField>

            <FormField label="Duration">
              <Select
                selectedOption={duration}
                onChange={({ detail }) => setDuration(detail.selectedOption)}
                options={durationOptions}
                disabled={isGenerating}
              />
            </FormField>

            <FormField label="Resolution">
              <Select
                selectedOption={resolution}
                onChange={({ detail }) => setResolution(detail.selectedOption)}
                options={resolutionOptions}
                disabled={isGenerating}
              />
            </FormField>

            <FormField label="Loop">
              <Select
                selectedOption={loop}
                onChange={({ detail }) => setLoop(detail.selectedOption)}
                options={loopOptions}
                disabled={isGenerating}
              />
            </FormField>
          </ColumnLayout>
        </SpaceBetween>
      </Container>

      {jobStatus && (
        <Container>
          <SpaceBetween size="m">
            <Box>
              <StatusIndicator type={
                jobStatus.status === 'completed' ? 'success' :
                jobStatus.status === 'failed' ? 'error' :
                'in-progress'
              }>
                {jobStatus.status.charAt(0).toUpperCase() + jobStatus.status.slice(1)}
              </StatusIndicator>
            </Box>
            <ProgressBar
              value={jobStatus.progress}
              label={jobStatus.message}
              description={`Job ID: ${jobStatus.job_id}`}
            />
          </SpaceBetween>
        </Container>
      )}

      <Box textAlign="center">
        <Button
          variant="primary"
          onClick={handleGenerateVideo}
          loading={isGenerating}
          disabled={isUploading}
          iconName="upload"
        >
          Generate Video
        </Button>
      </Box>
    </SpaceBetween>
  );
}

export default VideoGenerator;
