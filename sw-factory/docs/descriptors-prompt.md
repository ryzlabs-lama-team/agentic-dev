/plan I want to implement a desciptors system for the main documents: prds, stories, hlds, and plans. other documents we can leave untouched.

Use JSON or YAML whaever is more efficient for agents.

The idea is to split document sections into smaller documents, and have a descriptor file with reference to where to read the info.

Agents would be able to pick the pieces that are more relevant to the task they need to complete.

Desciptors could contain tags to classify the files or othe metadata that is relevant, for example status in the case of a task.

sf-factory agents should be able to read from the descriptors to find the information they look.