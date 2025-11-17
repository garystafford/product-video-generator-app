import React, { useState } from 'react';
import {
  AppLayout,
  TopNavigation,
  SideNavigation,
  ContentLayout,
  Header,
  SpaceBetween,
  Box
} from '@cloudscape-design/components';
import '@cloudscape-design/global-styles/index.css';

import VideoGenerator from './components/VideoGenerator';
import JobMonitor from './components/JobMonitor';
import VideoGallery from './components/VideoGallery';

function App() {
  const [activeView, setActiveView] = useState('generate');
  const [navigationOpen, setNavigationOpen] = useState(true);

  const navItems = [
    {
      type: 'link',
      text: 'Generate Video',
      href: '#generate',
      info: 'Create new product videos'
    },
    {
      type: 'link',
      text: 'Job Monitor',
      href: '#monitor',
      info: 'Track video generation progress'
    },
    {
      type: 'link',
      text: 'Video Gallery',
      href: '#gallery',
      info: 'View completed videos'
    },
    { type: 'divider' },
    {
      type: 'link',
      text: 'GitHub Repository',
      href: 'https://github.com/garystafford/product-video-generator',
      external: true,
      externalIconAriaLabel: 'Opens in a new tab'
    }
  ];

  const handleNavigation = (event) => {
    event.preventDefault();
    const href = event.detail.href.replace('#', '');
    setActiveView(href);
  };

  const renderContent = () => {
    switch (activeView) {
      case 'generate':
        return <VideoGenerator />;
      case 'monitor':
        return <JobMonitor />;
      case 'gallery':
        return <VideoGallery />;
      default:
        return <VideoGenerator />;
    }
  };

  return (
    <>
      <TopNavigation
        identity={{
          href: '#',
          title: 'Product Video Generator',
          logo: {
            src: '/video-editing-white.png',
            alt: 'Video Editing Logo'
          }
        }}
        utilities={[
          {
            type: 'button',
            text: 'AWS Console',
            href: 'https://console.aws.amazon.com',
            external: true,
            externalIconAriaLabel: 'Opens in new tab'
          },
          {
            type: 'menu-dropdown',
            text: 'Settings',
            items: [
              { id: 'settings', text: 'Preferences' },
              { id: 'support', text: 'Support' },
              { id: 'signout', text: 'Sign out' }
            ]
          }
        ]}
      />
      <AppLayout
        navigation={
          <SideNavigation
            activeHref={`#${activeView}`}
            header={{ href: '#', text: 'Navigation' }}
            items={navItems}
            onFollow={handleNavigation}
          />
        }
        navigationOpen={navigationOpen}
        onNavigationChange={({ detail }) => setNavigationOpen(detail.open)}
        content={
          <ContentLayout
            header={
              <Header
                variant="h1"
                description="Generate professional product videos using AI"
              >
                {activeView === 'generate' && 'Generate Video'}
                {activeView === 'monitor' && 'Job Monitor'}
                {activeView === 'gallery' && 'Video Gallery'}
              </Header>
            }
          >
            {renderContent()}
          </ContentLayout>
        }
        toolsHide={true}
      />
      <Box
        textAlign="center"
        padding={{ top: 's', bottom: 's' }}
        color="text-body-secondary"
        fontSize="body-s"
      >
        Gary A. Stafford, 2025
      </Box>
    </>
  );
}

export default App;
