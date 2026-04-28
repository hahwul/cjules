require "json"
require "yaml"

module Cjules
  module Models
    class GitHubBranch
      include JSON::Serializable
      include YAML::Serializable

      property displayName : String?
    end

    class GitHubRepo
      include JSON::Serializable
      include YAML::Serializable

      property owner : String?
      property repo : String?
      property isPrivate : Bool?
      property defaultBranch : GitHubBranch?
      property branches : Array(GitHubBranch)?
    end

    class Source
      include JSON::Serializable
      include YAML::Serializable

      property name : String?
      property id : String?
      property githubRepo : GitHubRepo?
    end

    class GitHubRepoContext
      include JSON::Serializable
      include YAML::Serializable

      property startingBranch : String?
    end

    class SourceContext
      include JSON::Serializable
      include YAML::Serializable

      property source : String?
      property githubRepoContext : GitHubRepoContext?
    end

    class PullRequest
      include JSON::Serializable
      include YAML::Serializable

      property url : String?
      property title : String?
      property description : String?
    end

    class SessionOutput
      include JSON::Serializable
      include YAML::Serializable

      property pullRequest : PullRequest?
    end

    class Session
      include JSON::Serializable
      include YAML::Serializable

      property name : String?
      property id : String?
      property prompt : String?
      property title : String?
      property state : String?
      property url : String?
      property sourceContext : SourceContext?
      property requirePlanApproval : Bool?
      property automationMode : String?
      property outputs : Array(SessionOutput)?
      property createTime : String?
      property updateTime : String?

      def short_id : String
        id || name.try(&.split("/").last) || "?"
      end

      def repo_display : String
        src = sourceContext.try(&.source) || ""
        # API uses slash-separated source IDs: sources/github/OWNER/REPO
        if m = src.match(/^sources\/github\/(.+)$/)
          m[1]
        else
          src
        end
      end
    end

    class Plan
      include JSON::Serializable
      include YAML::Serializable

      property id : String?
      property steps : Array(PlanStep)?
      property createTime : String?
    end

    class PlanStep
      include JSON::Serializable
      include YAML::Serializable

      property id : String?
      property index : Int32?
      property title : String?
      property description : String?
    end

    class GitPatch
      include JSON::Serializable
      include YAML::Serializable

      property baseCommitId : String?
      property unidiffPatch : String?
      property suggestedCommitMessage : String?
    end

    class ChangeSet
      include JSON::Serializable
      include YAML::Serializable

      property source : String?
      property gitPatch : GitPatch?
    end

    class BashOutput
      include JSON::Serializable
      include YAML::Serializable

      property command : String?
      property output : String?
      property exitCode : Int32?
    end

    class Media
      include JSON::Serializable
      include YAML::Serializable

      property mimeType : String?
      property data : String?
    end

    class Artifact
      include JSON::Serializable
      include YAML::Serializable

      property changeSet : ChangeSet?
      property bashOutput : BashOutput?
      property media : Media?
    end

    class PlanGenerated
      include JSON::Serializable
      include YAML::Serializable

      property plan : Plan?
    end

    class PlanApproved
      include JSON::Serializable
      include YAML::Serializable

      property planId : String?
    end

    class UserMessaged
      include JSON::Serializable
      include YAML::Serializable

      property userMessage : String?
    end

    class AgentMessaged
      include JSON::Serializable
      include YAML::Serializable

      property agentMessage : String?
    end

    class ProgressUpdated
      include JSON::Serializable
      include YAML::Serializable

      property title : String?
      property description : String?
    end

    class SessionCompleted
      include JSON::Serializable
      include YAML::Serializable
    end

    class SessionFailed
      include JSON::Serializable
      include YAML::Serializable

      property reason : String?
    end

    class Activity
      include JSON::Serializable
      include YAML::Serializable

      property name : String?
      property id : String?
      property originator : String?
      property description : String?
      property createTime : String?
      property artifacts : Array(Artifact)?
      property planGenerated : PlanGenerated?
      property planApproved : PlanApproved?
      property userMessaged : UserMessaged?
      property agentMessaged : AgentMessaged?
      property progressUpdated : ProgressUpdated?
      property sessionCompleted : SessionCompleted?
      property sessionFailed : SessionFailed?

      def event_type : String
        return "plan_generated" if planGenerated
        return "plan_approved" if planApproved
        return "user_messaged" if userMessaged
        return "agent_messaged" if agentMessaged
        return "progress_updated" if progressUpdated
        return "session_completed" if sessionCompleted
        return "session_failed" if sessionFailed
        "unknown"
      end
    end

    class ListSessionsResponse
      include JSON::Serializable

      property sessions : Array(Session)?
      property nextPageToken : String?
    end

    class ListSourcesResponse
      include JSON::Serializable

      property sources : Array(Source)?
      property nextPageToken : String?
    end

    class ListActivitiesResponse
      include JSON::Serializable

      property activities : Array(Activity)?
      property nextPageToken : String?
    end
  end
end
