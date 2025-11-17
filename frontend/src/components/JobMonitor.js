import React, { useState, useEffect } from 'react';
import {
  Container,
  Table,
  Box,
  SpaceBetween,
  Button,
  StatusIndicator,
  ProgressBar,
  Header,
  Badge
} from '@cloudscape-design/components';
import axios from 'axios';

function JobMonitor() {
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState(false);
  const [selectedItems, setSelectedItems] = useState([]);

  const fetchJobs = async () => {
    try {
      setLoading(true);
      const response = await axios.get('/api/jobs');
      setJobs(response.data.jobs || []);
    } catch (error) {
      console.error('Failed to fetch jobs:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchJobs();

    // Auto-refresh every 3 seconds
    const interval = setInterval(fetchJobs, 3000);

    return () => clearInterval(interval);
  }, []);

  const getStatusIndicator = (status) => {
    switch (status) {
      case 'completed':
        return <StatusIndicator type="success">Completed</StatusIndicator>;
      case 'failed':
        return <StatusIndicator type="error">Failed</StatusIndicator>;
      case 'pending':
        return <StatusIndicator type="pending">Pending</StatusIndicator>;
      case 'uploading':
      case 'generating':
      case 'downloading':
      case 'processing':
        return <StatusIndicator type="in-progress">
          {status.charAt(0).toUpperCase() + status.slice(1)}
        </StatusIndicator>;
      default:
        return <StatusIndicator type="info">{status}</StatusIndicator>;
    }
  };

  const getStatusBadge = (status) => {
    const colorMap = {
      'completed': 'green',
      'failed': 'red',
      'pending': 'grey',
      'uploading': 'blue',
      'generating': 'blue',
      'downloading': 'blue',
      'processing': 'blue'
    };

    return <Badge color={colorMap[status] || 'grey'}>{status}</Badge>;
  };

  const formatDate = (isoString) => {
    const date = new Date(isoString);
    return date.toLocaleString();
  };

  const columnDefinitions = [
    {
      id: 'product_name',
      header: 'Product',
      cell: item => item.product_name,
      sortingField: 'product_name'
    },
    {
      id: 'status',
      header: 'Status',
      cell: item => getStatusIndicator(item.status),
      sortingField: 'status'
    },
    {
      id: 'progress',
      header: 'Progress',
      cell: item => (
        <Box>
          <ProgressBar
            value={item.progress}
            variant="standalone"
            label={`${item.progress}%`}
            description={item.message}
          />
        </Box>
      )
    },
    {
      id: 'created_at',
      header: 'Created',
      cell: item => formatDate(item.created_at),
      sortingField: 'created_at'
    },
    {
      id: 'updated_at',
      header: 'Last Updated',
      cell: item => formatDate(item.updated_at),
      sortingField: 'updated_at'
    },
    {
      id: 'job_id',
      header: 'Job ID',
      cell: item => (
        <Box fontSize="body-s" color="text-body-secondary">
          {item.job_id.slice(0, 8)}...
        </Box>
      )
    }
  ];

  const sortedJobs = [...jobs].sort((a, b) => {
    return new Date(b.created_at) - new Date(a.created_at);
  });

  const activeJobs = sortedJobs.filter(job =>
    ['pending', 'uploading', 'generating', 'downloading', 'processing'].includes(job.status)
  );

  const completedJobs = sortedJobs.filter(job => job.status === 'completed');
  const failedJobs = sortedJobs.filter(job => job.status === 'failed');

  return (
    <SpaceBetween size="l">
      <Container>
        <SpaceBetween size="m">
          <Header
            variant="h3"
            counter={`(${jobs.length})`}
            actions={
              <Button
                iconName="refresh"
                onClick={fetchJobs}
                loading={loading}
              >
                Refresh
              </Button>
            }
          >
            Job Statistics
          </Header>

          <Box>
            <SpaceBetween direction="horizontal" size="xl">
              <Box>
                <Box variant="awsui-key-label">Active Jobs</Box>
                <Box fontSize="display-l" fontWeight="bold" color="text-status-info">
                  {activeJobs.length}
                </Box>
              </Box>
              <Box>
                <Box variant="awsui-key-label">Completed</Box>
                <Box fontSize="display-l" fontWeight="bold" color="text-status-success">
                  {completedJobs.length}
                </Box>
              </Box>
              <Box>
                <Box variant="awsui-key-label">Failed</Box>
                <Box fontSize="display-l" fontWeight="bold" color="text-status-error">
                  {failedJobs.length}
                </Box>
              </Box>
              <Box>
                <Box variant="awsui-key-label">Total</Box>
                <Box fontSize="display-l" fontWeight="bold">
                  {jobs.length}
                </Box>
              </Box>
            </SpaceBetween>
          </Box>
        </SpaceBetween>
      </Container>

      {activeJobs.length > 0 && (
        <Container
          header={
            <Header variant="h2" counter={`(${activeJobs.length})`}>
              Active Jobs
            </Header>
          }
        >
          <Table
            columnDefinitions={columnDefinitions}
            items={activeJobs}
            loadingText="Loading jobs"
            loading={loading}
            trackBy="job_id"
            empty={
              <Box textAlign="center" color="inherit">
                <b>No active jobs</b>
                <Box padding={{ bottom: 's' }} variant="p" color="inherit">
                  No jobs are currently in progress.
                </Box>
              </Box>
            }
            sortingDisabled
          />
        </Container>
      )}

      <Container
        header={
          <Header variant="h2" counter={`(${sortedJobs.length})`}>
            All Jobs
          </Header>
        }
      >
        <Table
          columnDefinitions={columnDefinitions}
          items={sortedJobs}
          loadingText="Loading jobs"
          loading={loading}
          trackBy="job_id"
          selectedItems={selectedItems}
          onSelectionChange={({ detail }) => setSelectedItems(detail.selectedItems)}
          selectionType="multi"
          empty={
            <Box textAlign="center" color="inherit">
              <b>No jobs</b>
              <Box padding={{ bottom: 's' }} variant="p" color="inherit">
                No jobs have been created yet.
              </Box>
            </Box>
          }
          filter={null}
          header={null}
        />
      </Container>
    </SpaceBetween>
  );
}

export default JobMonitor;
