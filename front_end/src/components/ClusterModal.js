// src/components/ClusterModal.js
import { Modal, Button } from "@cloudscape-design/components";
import React, { useState } from "react";

const ClusterModal = ({ cluster, articles, onClose, visible }) => {
  // State to manage visibility of each article's full text
  const [visibleArticles, setVisibleArticles] = useState({});

  // Function to toggle article text visibility
  const toggleArticleVisibility = (id) => {
    setVisibleArticles((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  // Helper function to format date
  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  return (
    <Modal
      onDismiss={onClose}
      header={cluster ? cluster.description : "Loading..."}
      footer={<Button onClick={onClose}>Close</Button>}
      visible={visible}
      size="large"
    >
      {articles && articles.length > 0 ? (
        articles.map((article) => (
          <div key={article.SK}>
            <h3>{article.title} </h3>
            <medium>{formatDate(article.publication_date)}</medium>
            <p>{article.summary}</p>
            <Button onClick={() => toggleArticleVisibility(article.SK)}>
              {visibleArticles[article.SK]
                ? "Hide Full Text"
                : "Show Full Text"}
            </Button>
            {visibleArticles[article.SK] && <p>{article.text}</p>}
            <hr></hr>
          </div>
        ))
      ) : (
        <p>No articles found.</p>
      )}
    </Modal>
  );
};

export default ClusterModal;
