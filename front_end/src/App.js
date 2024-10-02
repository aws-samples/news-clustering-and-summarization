import React, { useState, useEffect } from 'react';
import './App.css';
import ClusterList from './components/ClusterList';
import { AppLayout, Toggle, Box, SpaceBetween, Header, Icon, Button } from '@cloudscape-design/components';
import { applyMode, Mode } from '@cloudscape-design/global-styles';
import awsConfig from './aws-exports'; // Path to your aws-exports file
import { Amplify } from 'aws-amplify';
import { Authenticator, View, Image, Heading, components } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';




console.log('Configuring Amplify with:', awsConfig);
Amplify.configure(awsConfig);
// console.log('Amplify configuration:', Amplify.configure());

function App() {
  const [darkMode, setDarkMode] = useState(false);

  const toggleDarkMode = () => {
    setDarkMode(!darkMode);
  };

  applyMode(darkMode ? Mode.Dark : Mode.Light);


// Custom Header for the Sign In page
const SignInHeader = () => {
  return (
    <View textAlign="center" padding="large">
      <Image
        alt="App Logo"
        src="favicon.ico" // Ensure the path is correct based on your project structure
        style={{ width: 50, height: 50 }} // Adjust size as necessary
      />
      <Heading level={3}>Near Real Time News Clustering and Summarization Demo</Heading>
    </View>
  );
};


  return (
    <Authenticator
      hideSignUp={true}
      loginMechanisms={['email']}
      components={{
        Header: SignInHeader, // Use your custom Header for the Sign In page
      }}
    >
        {({ signOut }) => (
           <div>
           <AppLayout
            mode={darkMode ? Mode.Dark : Mode.Light}
            content={
              <div className="App">
                <ClusterList />
              </div>
            }
            navigationHide
            tools={
              <Box padding="m">
                <Header variant="h2" info={<Icon name="settings" />}>Settings</Header>
                <br></br>
                <SpaceBetween direction="horizontal" size="m">
                  Dark Mode
                  <Toggle
                    checked={darkMode}
                    onChange={toggleDarkMode}
                    ariaLabel="Toggle dark mode"
                  />
                </SpaceBetween>
                <br></br>
                <Button variant='primary' onClick={signOut}>Sign out</Button>

              </Box>
          }
        />
       </div>
   )}
          
    </Authenticator>



  );
}

export default App;
