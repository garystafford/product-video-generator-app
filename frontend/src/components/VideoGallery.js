import React, { useState, useEffect } from 'react';
import {
  Container,
  Cards,
  Box,
  SpaceBetween,
  Button,
  Header,
  Badge,
  Modal,
  ColumnLayout
} from '@cloudscape-design/components';
import axios from 'axios';

function VideoGallery() {
  const [videos, setVideos] = useState([]);
  const [loading, setLoading] = useState(false);
  const [selectedVideo, setSelectedVideo] = useState(null);
  const [showVideoModal, setShowVideoModal] = useState(false);

  const fetchVideos = async () => {
    try {
      setLoading(true);
      const response = await axios.get('/api/videos');
      setVideos(response.data.videos || []);
    } catch (error) {
      console.error('Failed to fetch videos:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchVideos();
  }, []);

  const handleViewVideo = (video) => {
    setSelectedVideo(video);
    setShowVideoModal(true);
  };

  const handleDownload = (videoId, original = false) => {
    const url = original
      ? `/api/videos/download/${videoId}?original=true`
      : `/api/videos/download/${videoId}`;

    window.open(url, '_blank');
  };

  const handleDelete = async (video) => {
    if (!window.confirm(`Are you sure you want to delete video "${video.product_name}"?`)) {
      return;
    }

    try {
      await axios.delete(`/api/videos/${video.video_id}`);
      fetchVideos();
    } catch (error) {
      console.error('Failed to delete video:', error);
      alert(`Delete failed: ${error.response?.data?.detail || error.message}`);
    }
  };

  const formatDate = (isoString) => {
    const date = new Date(isoString);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
  };

  return (
    <SpaceBetween size="l">
      <Container
        header={
          <Header
            variant="h2"
            counter={`(${videos.length})`}
            actions={
              <Button iconName="refresh" onClick={fetchVideos} loading={loading}>
                Refresh
              </Button>
            }
          >
            Generated Videos
          </Header>
        }
      >
        {videos.length === 0 ? (
          <Box textAlign="center" color="inherit" padding={{ vertical: 'xxl' }}>
            <Box variant="strong" color="inherit">
              No videos yet
            </Box>
            <Box variant="p" color="inherit" padding={{ top: 's' }}>
              Generate your first video to see it here
            </Box>
          </Box>
        ) : (
          <Cards
            cardDefinition={{
              header: video => (
                <SpaceBetween direction="horizontal" size="s">
                  <Box variant="h3">{video.product_name}</Box>
                  <Badge color="green">{video.status}</Badge>
                </SpaceBetween>
              ),
              sections: [
                {
                  id: 'thumbnail',
                  content: video => (
                    video.start_keyframe && (
                      <Box textAlign="center">
                        <img
                          src={`/api/keyframes/${video.product_name}/start`}
                          alt="Start frame"
                          style={{
                            width: '100%',
                            maxWidth: '200px',
                            maxHeight: '200px',
                            objectFit: 'contain',
                            borderRadius: '8px',
                            cursor: 'pointer'
                          }}
                          onClick={() => handleViewVideo(video)}
                        />
                      </Box>
                    )
                  )
                },
                {
                  id: 'details',
                  content: video => (
                    <Box fontSize="body-s" color="text-body-secondary">
                      <SpaceBetween size="xs">
                        <Box>
                          <strong>Prompt:</strong> {video.prompt?.substring(0, 100)}
                          {video.prompt?.length > 100 && '...'}
                        </Box>
                        <Box>
                          <strong>Created:</strong> {formatDate(video.created_at)}
                        </Box>
                      </SpaceBetween>
                    </Box>
                  )
                },
                {
                  id: 'actions',
                  content: video => (
                    <SpaceBetween size="xs">
                      <Button
                        variant="primary"
                        onClick={() => handleViewVideo(video)}
                        fullWidth
                        iconName="video-on"
                      >
                        Play Video
                      </Button>

                      <ColumnLayout columns={2}>
                        <Button
                          onClick={() => handleDownload(video.video_id)}
                          fullWidth
                          iconName="download"
                        >
                          Download
                        </Button>
                        <Button
                          onClick={() => handleDelete(video)}
                          fullWidth
                          iconName="remove"
                        >
                          Delete
                        </Button>
                      </ColumnLayout>

                      <Button
                        onClick={() => handleDownload(video.video_id, true)}
                        fullWidth
                        variant="normal"
                      >
                        Download Original
                      </Button>

                      {video.s3_uri && (
                        <Button
                          onClick={() => window.open(video.s3_uri.replace('s3://', 'https://s3.console.aws.amazon.com/s3/object/'), '_blank')}
                          fullWidth
                          variant="normal"
                          iconName="external"
                        >
                          View in S3
                        </Button>
                      )}
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
            items={videos}
            empty={
              <Box textAlign="center" color="text-body-secondary">
                No videos available
              </Box>
            }
          />
        )}
      </Container>

      <Modal
        visible={showVideoModal}
        onDismiss={() => setShowVideoModal(false)}
        header={selectedVideo?.product_name}
        size="large"
        footer={
          <Box float="right">
            <SpaceBetween direction="horizontal" size="xs">
              <Button
                variant="link"
                onClick={() => setShowVideoModal(false)}
              >
                Close
              </Button>
              <Button
                variant="primary"
                onClick={() => handleDownload(selectedVideo?.video_id)}
                iconName="download"
              >
                Download
              </Button>
            </SpaceBetween>
          </Box>
        }
      >
        {selectedVideo && (
          <SpaceBetween size="l">
            <Box textAlign="center">
              <video
                controls
                autoPlay
                loop
                style={{
                  maxWidth: '100%',
                  maxHeight: '70vh',
                  borderRadius: '8px'
                }}
                key={selectedVideo.video_id}
              >
                <source
                  src={`/api/videos/download/${selectedVideo.video_id}`}
                  type="video/mp4"
                />
                Your browser does not support the video tag.
              </video>
            </Box>

            <Container>
              <ColumnLayout columns={2} variant="text-grid">
                <SpaceBetween size="xs">
                  <Box variant="awsui-key-label">Product Name</Box>
                  <Box>{selectedVideo.product_name}</Box>
                </SpaceBetween>

                <SpaceBetween size="xs">
                  <Box variant="awsui-key-label">Status</Box>
                  <Badge color="green">{selectedVideo.status}</Badge>
                </SpaceBetween>

                <SpaceBetween size="xs">
                  <Box variant="awsui-key-label">Created</Box>
                  <Box>{formatDate(selectedVideo.created_at)}</Box>
                </SpaceBetween>

                <SpaceBetween size="xs">
                  <Box variant="awsui-key-label">Prompt</Box>
                  <Box>{selectedVideo.prompt}</Box>
                </SpaceBetween>

                {selectedVideo.s3_uri && (
                  <SpaceBetween size="xs">
                    <Box variant="awsui-key-label">S3 Location</Box>
                    <Box>
                      <a
                        href={selectedVideo.s3_uri.replace('s3://', 'https://s3.console.aws.amazon.com/s3/object/')}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ color: '#0972d3', textDecoration: 'none' }}
                      >
                        {selectedVideo.s3_uri}
                      </a>
                    </Box>
                  </SpaceBetween>
                )}
              </ColumnLayout>
            </Container>

            <Container header={<Header variant="h3">Keyframes</Header>}>
              <ColumnLayout columns={2}>
                {selectedVideo.start_keyframe && (
                  <Box textAlign="center">
                    <Box variant="awsui-key-label" margin={{ bottom: 's' }}>
                      Start Frame
                    </Box>
                    <img
                      src={`/api/keyframes/${selectedVideo.product_name}/start`}
                      alt="Start frame"
                      style={{
                        width: '100%',
                        maxWidth: '200px',
                        maxHeight: '300px',
                        objectFit: 'contain',
                        borderRadius: '8px'
                      }}
                    />
                  </Box>
                )}

                {selectedVideo.end_keyframe && (
                  <Box textAlign="center">
                    <Box variant="awsui-key-label" margin={{ bottom: 's' }}>
                      End Frame
                    </Box>
                    <img
                      src={`/api/keyframes/${selectedVideo.product_name}/end`}
                      alt="End frame"
                      style={{
                        width: '100%',
                        maxWidth: '200px',
                        maxHeight: '300px',
                        objectFit: 'contain',
                        borderRadius: '8px'
                      }}
                    />
                  </Box>
                )}
              </ColumnLayout>
            </Container>
          </SpaceBetween>
        )}
      </Modal>
    </SpaceBetween>
  );
}

export default VideoGallery;
