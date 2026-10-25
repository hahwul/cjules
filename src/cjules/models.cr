require "json"

module Cjules
  module Models
    class GitHubBranch
      include JSON::Serializable

      property displayName : String?
    end

    class GitHubRepo
      include JSON::Serializable

      property owner : String?
      property repo : String?
      property isPrivate : Bool?
      property defaultBranch : GitHubBranch?
      property branches : Array(GitHubBranch)?
    end

    class Source
      include JSON::Serializable

      property name : String?
      property id : String?
      property githubRepo : GitHubRepo?
    end

    class GitHubRepoContext
      include JSON::Serializable

      property startingBranch : String?
    end

    class SourceContext
      include JSON::Serializable

      property source : String?
      property githubRepoContext : GitHubRepoContext?
    end

    class PullRequest
      include JSON::Serializable

      property url : String?
      property title : String?
      property description : String?
    end

    class SessionOutput
      include JSON::Serializable

      property pullRequest : PullRequest?
    end

    class Session
      include JSON::Serializable

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

      property id : String?
      property steps : Array(PlanStep)?
      property createTime : String?
    end

    class PlanStep
      include JSON::Serializable

      property id : String?
      property index : Int32?
      property title : String?
      property description : String?
    end

    class GitPatch
      include JSON::Serializable

      property baseCommitId : String?
      property unidiffPatch : String?
      property suggestedCommitMessage : String?
    end

    class ChangeSet
      include JSON::Serializable

      property source : String?
      property gitPatch : GitPatch?
    end

    class BashOutput
      include JSON::Serializable

      property command : String?
      property output : String?
      property exitCode : Int32?
    end

    class Media
      include JSON::Serializable

      property mimeType : String?
      property data : String?
    end

    class Artifact
      include JSON::Serializable

      property changeSet : ChangeSet?
      property bashOutput : BashOutput?
      property media : Media?
    end

    class PlanGenerated
      include JSON::Serializable

      property plan : Plan?
    end

    class PlanApproved
      include JSON::Serializable

      property planId : String?
    end

    class UserMessaged
      include JSON::Serializable

      property userMessage : String?
    end

    class AgentMessaged
      include JSON::Serializable

      property agentMessage : String?
    end

    class ProgressUpdated
      include JSON::Serializable

      property title : String?
      property description : String?
    end

    class SessionCompleted
      include JSON::Serializable
    end

    class SessionFailed
      include JSON::Serializable

      property reason : String?
    end

    class Activity
      include JSON::Serializable

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
