// src/components/ClusterList.js
import React, { useState, useEffect, useRef } from "react";
import AWS from "aws-sdk";
import {
  Button,
  Table,
  Box,
  ProgressBar,
  SpaceBetween,
} from "@cloudscape-design/components";
import { fetchAuthSession } from "@aws-amplify/auth";
import ClusterModal from "./ClusterModal";
import awsConfig from "../aws-exports";

const refreshInterval = 5000;

const ClusterList = () => {
  const [clusters, setClusters] = useState([]);
  const [selectedCluster, setSelectedCluster] = useState(null);
  const [totalArticles, setTotalArticles] = useState(0);
  const [isModalVisible, setModalVisible] = useState(false);
  const [progress, setProgress] = useState(0); // Initialize progress at 0%
  const [secondsRemaining, setSecondsRemaining] = useState(
    refreshInterval / 1000
  ); // Initialize countdown

  const dynamoDbRef = useRef();

  useEffect(() => {
    const configureAWS = async () => {
      const session = await fetchAuthSession();
      const { accessKeyId, secretAccessKey, sessionToken } =
        session.credentials;
      AWS.config.update({
        region: awsConfig.aws_cognito_region,
        credentials: new AWS.Credentials(
          accessKeyId,
          secretAccessKey,
          sessionToken
        ),
      });
      dynamoDbRef.current = new AWS.DynamoDB.DocumentClient();
      fetchClusters();
    };
    configureAWS();
  }, []);

  useEffect(() => {
    const intervalId = setInterval(() => {
      fetchClusters();
    }, refreshInterval);

    const progressId = setInterval(() => {
      setProgress(
        (prevProgress) => (prevProgress + (1000 / refreshInterval) * 100) % 100
      );
      setSecondsRemaining((prevSeconds) =>
        prevSeconds <= 1 ? refreshInterval / 1000 : prevSeconds - 1
      );
    }, 1000);

    return () => {
      clearInterval(intervalId);
      clearInterval(progressId);
    };
  }, []);

  const fetchClusters = async () => {
    if (!dynamoDbRef.current) {
      console.log("DynamoDB client not initialized");
      return;
    }
    let lastEvaluatedKey = null;
    const allItems = [];
    let articlesCount = 0;
    const params = {
      TableName: "cluster-table-clustering-demo2",
    };

    do {
      if (lastEvaluatedKey) {
        params.ExclusiveStartKey = lastEvaluatedKey;
      }
      const data = await dynamoDbRef.current.scan(params).promise();
      allItems.push(...data.Items);
      lastEvaluatedKey = data.LastEvaluatedKey;
    } while (lastEvaluatedKey);

    const articlesByCluster = allItems.reduce((acc, item) => {
      if (item.is_cluster) {
        acc[item.PK] = acc[item.PK] || [];
      } else if (item.SK.startsWith("ARTICLE#")) {
        if (item.publication_date) {
          articlesCount++;
          if (acc[item.PK]) {
            acc[item.PK].push(item);
          }
        }
      }
      return acc;
    }, {});

    const newClusters = allItems
      .filter(
        (item) =>
          item.is_cluster &&
          item.generated_summary &&
          articlesByCluster[item.PK] &&
          articlesByCluster[item.PK].length > 2
      )
      .map((cluster) => ({
        ...cluster,
        articles: articlesByCluster[cluster.PK],
        number_of_articles: articlesByCluster[cluster.PK].length,
      }))
      .sort((a, b) => b.number_of_articles - a.number_of_articles);

    setClusters(newClusters);
    setTotalArticles(articlesCount);
  };

  const handleViewArticles = (cluster) => {
    console.log("Opening modal for cluster:", cluster.PK);
    setSelectedCluster(cluster);
    setModalVisible(true); // Set the modal to be visible
  };

  const wrapStyleSummary = {
    whiteSpace: "normal", // Allow the text to wrap to the next line
    wordBreak: "break-word", // Ensure words break correctly at the end of the line
    maxWidth: "600px", // Set a maximum width for the cell content
    textAlign: "justify", // Center the text
  };

  const wrapStyleTitle = {
    whiteSpace: "normal", // Allow the text to wrap to the next line
    wordBreak: "break-word", // Ensure words break correctly at the end of the line
    maxWidth: "150px", // Set a maximum width for the cell content
    textAlign: "center",
  };

  const wrapStyleNumberOfArticles = {
    whiteSpace: "normal", // Allow the text to wrap to the next line
    wordBreak: "break-word", // Ensure words break correctly at the end of the line
    maxWidth: "100px", // Set a maximum width for the cell content
    textAlign: "center",
  };

  // Column definitions using inline styles
  const columnDefinitions = [
    {
      header: "Title",
      cell: (item) => <div style={wrapStyleTitle}>{item.description}</div>,
    },
    {
      header: "Summary",
      cell: (item) => (
        <div style={wrapStyleSummary}>{item.generated_summary}</div>
      ),
    },
    {
      header: "Articles",
      cell: (item) => (
        <div style={wrapStyleNumberOfArticles}>{item.number_of_articles}</div>
      ),
    },
    {
      header: "View",
      cell: (item) => (
        <Button onClick={() => handleViewArticles(item)}>View Articles</Button>
      ),
    },
  ];

  return (
    <Box textAlign="center" padding="m">
      <SpaceBetween direction="vertical" size="s">
        <h1 textAlign="center">
          {" "}
          Near Real Time News Clustering and Summarization Demo
        </h1>
        <b>
          Total Clusters: {clusters.length} | Total Articles: {totalArticles}
        </b>
        <div style={{ width: "30%", margin: "0 auto" }}>
          <ProgressBar
            value={progress}
            label={`Next refresh in ${secondsRemaining} seconds`}
          />
        </div>

        <Table
          items={clusters}
          columnDefinitions={columnDefinitions}
          trackBy="PK"
        />
        {selectedCluster && (
          <ClusterModal
            cluster={selectedCluster}
            articles={selectedCluster.articles} // Pass articles directly to the modal
            onClose={() => {
              setSelectedCluster(null);
              setModalVisible(false); // Hide the modal when closed
            }}
            visible={isModalVisible} // Control visibility with state
          />
        )}
      </SpaceBetween>
    </Box>
  );
};

export default ClusterList;
